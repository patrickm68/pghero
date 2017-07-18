module PgHero
  module Methods
    module QueryStats
      def query_stats(historical: false, start_at: nil, end_at: nil, min_average_time: nil, min_calls: nil, **options)
        current_query_stats = historical && end_at && end_at < Time.now ? [] : current_query_stats(options)
        historical_query_stats = historical ? historical_query_stats(start_at: start_at, end_at: end_at, **options) : []

        query_stats = combine_query_stats((current_query_stats + historical_query_stats).group_by { |q| [q["query_hash"], q["user"]] })
        query_stats = combine_query_stats(query_stats.group_by { |q| [normalize_query(q["query"]), q["user"]] })

        # add percentages
        all_queries_total_minutes = [current_query_stats, historical_query_stats].sum { |s| (s.first || {})["all_queries_total_minutes"] || 0 }
        query_stats.each do |query|
          query["average_time"] = query["total_minutes"] * 1000 * 60 / query["calls"]
          query["total_percent"] = query["total_minutes"] * 100.0 / all_queries_total_minutes
        end

        sort = options[:sort] || "total_minutes"
        query_stats = query_stats.sort_by { |q| -q[sort] }.first(100)
        if min_average_time
          query_stats.reject! { |q| q["average_time"] < min_average_time }
        end
        if min_calls
          query_stats.reject! { |q| q["calls"] < min_calls }
        end
        query_stats
      end

      def query_stats_available?
        select_all("SELECT COUNT(*) AS count FROM pg_available_extensions WHERE name = 'pg_stat_statements'").first["count"].to_i > 0
      end

      def query_stats_enabled?
        query_stats_extension_enabled? && query_stats_readable?
      end

      def query_stats_extension_enabled?
        select_all("SELECT COUNT(*) AS count FROM pg_extension WHERE extname = 'pg_stat_statements'").first["count"].to_i > 0
      end

      def query_stats_readable?
        select_all("SELECT * FROM pg_stat_statements LIMIT 1")
        true
      rescue ActiveRecord::StatementInvalid
        false
      end

      def enable_query_stats
        execute("CREATE EXTENSION pg_stat_statements")
      end

      def disable_query_stats
        execute("DROP EXTENSION IF EXISTS pg_stat_statements")
        true
      end

      def reset_query_stats
        if query_stats_enabled?
          execute("SELECT pg_stat_statements_reset()")
          true
        else
          false
        end
      end

      # http://stackoverflow.com/questions/20582500/how-to-check-if-a-table-exists-in-a-given-schema
      def historical_query_stats_enabled?
        # TODO use schema from config
        # make sure primary database is PostgreSQL first
        table_exists?("pghero_query_stats") && capture_query_stats?
      end

      def supports_query_hash?
        @supports_query_hash ||= server_version_num >= 90400 && historical_query_stats_enabled? && PgHero::QueryStats.column_names.include?("query_hash")
      end

      def supports_query_stats_user?
        @supports_query_stats_user ||= historical_query_stats_enabled? && PgHero::QueryStats.column_names.include?("user")
      end

      def insert_stats(table, columns, values)
        values = values.map { |v| "(#{v.map { |v2| quote(v2) }.join(",")})" }.join(",")
        columns = columns.map { |v| quote_table_name(v) }.join(",")
        stats_connection.execute("INSERT INTO #{quote_table_name(table)} (#{columns}) VALUES #{values}")
      end

      # resetting query stats will reset across the entire Postgres instance
      # this is problematic if multiple PgHero databases use the same Postgres instance
      #
      # to get around this, we capture queries for every Postgres database before we
      # reset query stats for the Postgres instance with the `capture_query_stats` option
      def capture_query_stats
        return if config["capture_query_stats"] && config["capture_query_stats"] != true

        # get all databases that use same query stats and build mapping
        mapping = {id => database_name}
        PgHero.databases.select { |_, d| d.config["capture_query_stats"] == id }.each do |_, d|
          mapping[d.id] = d.database_name
        end

        now = Time.now

        query_stats = {}
        mapping.each do |database_id, database_name|
          query_stats[database_id] = query_stats(limit: 1000000, database: database_name)
        end

        if query_stats.any? { |_, v| v.any? } && reset_query_stats
          query_stats.each do |db_id, db_query_stats|
            if db_query_stats.any?
              supports_query_hash = PgHero.databases[db_id].supports_query_hash?
              supports_query_stats_user = PgHero.databases[db_id].supports_query_stats_user?

              values =
                db_query_stats.map do |qs|
                  values = [
                    db_id,
                    qs["query"],
                    qs["total_minutes"] * 60 * 1000,
                    qs["calls"],
                    now
                  ]
                  values << qs["query_hash"] if supports_query_hash
                  values << qs["user"] if supports_query_stats_user
                  values
                end

              columns = %w[database query total_time calls captured_at]
              columns << "query_hash" if supports_query_hash
              columns << "user" if supports_query_stats_user

              insert_stats("pghero_query_stats", columns, values)
            end
          end
        end
      end

      def slow_queries(query_stats: nil, **options)
        query_stats ||= self.query_stats(options)
        query_stats.select { |q| q["calls"].to_i >= slow_query_calls.to_i && q["average_time"].to_i >= slow_query_ms.to_i }
      end

      def query_hash_stats(query_hash)
        if historical_query_stats_enabled? && supports_query_hash?
          start_at = 24.hours.ago
          select_all_stats <<-SQL
            SELECT
              captured_at,
              total_time / 1000 / 60 AS total_minutes,
              (total_time / calls) AS average_time,
              calls
            FROM
              pghero_query_stats
            WHERE
              database = #{quote(id)}
              AND captured_at >= #{quote(start_at)}
              AND query_hash = #{quote(query_hash)}
            ORDER BY
              1 ASC
          SQL
        else
          []
        end
      end

      private

      def stats_connection
        ::PgHero::QueryStats.connection
      end

      # http://www.craigkerstiens.com/2013/01/10/more-on-postgres-performance/
      def current_query_stats(limit: nil, sort: nil, database: nil, query_hash: nil)
        if query_stats_enabled?
          limit ||= 100
          sort ||= "total_minutes"
          select_all <<-SQL
            WITH query_stats AS (
              SELECT
                LEFT(query, 10000) AS query,
                #{supports_query_hash? ? "queryid" : "md5(query)"} AS query_hash,
                #{supports_query_stats_user? ? "rolname" : "NULL::text"} AS user,
                (total_time / 1000 / 60) AS total_minutes,
                (total_time / calls) AS average_time,
                calls
              FROM
                pg_stat_statements
              INNER JOIN
                pg_database ON pg_database.oid = pg_stat_statements.dbid
              INNER JOIN
                pg_roles ON pg_roles.oid = pg_stat_statements.userid
              WHERE
                pg_database.datname = #{database ? quote(database) : "current_database()"}
                #{query_hash ? "AND queryid = #{quote(query_hash)}" : nil}
            )
            SELECT
              query,
              query_hash,
              query_stats.user,
              total_minutes,
              average_time,
              calls,
              total_minutes * 100.0 / (SELECT SUM(total_minutes) FROM query_stats) AS total_percent,
              (SELECT SUM(total_minutes) FROM query_stats) AS all_queries_total_minutes
            FROM
              query_stats
            ORDER BY
              #{quote_table_name(sort)} DESC
            LIMIT #{limit.to_i}
          SQL
        else
          []
        end
      end

      def historical_query_stats(sort: nil, start_at: nil, end_at: nil, query_hash: nil)
        if historical_query_stats_enabled?
          sort ||= "total_minutes"
          select_all_stats <<-SQL
            WITH query_stats AS (
              SELECT
                #{supports_query_hash? ? "query_hash" : "md5(query)"} AS query_hash,
                #{supports_query_stats_user? ? "pghero_query_stats.user" : "NULL::text"} AS user,
                array_agg(LEFT(query, 10000) ORDER BY REPLACE(LEFT(query, 1000), '?', '!') COLLATE "C" ASC) AS query,
                (SUM(total_time) / 1000 / 60) AS total_minutes,
                (SUM(total_time) / SUM(calls)) AS average_time,
                SUM(calls) AS calls
              FROM
                pghero_query_stats
              WHERE
                database = #{quote(id)}
                #{supports_query_hash? ? "AND query_hash IS NOT NULL" : ""}
                #{start_at ? "AND captured_at >= #{quote(start_at)}" : ""}
                #{end_at ? "AND captured_at <= #{quote(end_at)}" : ""}
                #{query_hash ? "AND query_hash = #{quote(query_hash)}" : ""}
              GROUP BY
                1, 2
            )
            SELECT
              query_hash,
              query_stats.user,
              query[1] AS query,
              query[array_length(query, 1)] AS explainable_query,
              total_minutes,
              average_time,
              calls,
              total_minutes * 100.0 / (SELECT SUM(total_minutes) FROM query_stats) AS total_percent,
              (SELECT SUM(total_minutes) FROM query_stats) AS all_queries_total_minutes
            FROM
              query_stats
            ORDER BY
              #{quote_table_name(sort)} DESC
            LIMIT 100
          SQL
        else
          []
        end
      end

      def server_version_num
        @server_version ||= select_all("SHOW server_version_num").first["server_version_num"].to_i
      end

      def combine_query_stats(grouped_stats)
        query_stats = []
        grouped_stats.each do |_, stats2|
          value = {
            "query" => (stats2.find { |s| s["query"] } || {})["query"],
            "user" => (stats2.find { |s| s["user"] } || {})["user"],
            "query_hash" => (stats2.find { |s| s["query"] } || {})["query_hash"],
            "total_minutes" => stats2.sum { |s| s["total_minutes"] },
            "calls" => stats2.sum { |s| s["calls"] }.to_i,
            "all_queries_total_minutes" => stats2.sum { |s| s["all_queries_total_minutes"] }
          }
          value["total_percent"] = value["total_minutes"] * 100.0 / value["all_queries_total_minutes"]
          value["explainable_query"] = stats2.map { |s| s["explainable_query"] }.select { |q| q && explainable?(q) }.first
          query_stats << value
        end
        query_stats
      end

      def explainable?(query)
        query =~ /select/i && !query.include?("?)") && !query.include?("= ?") && !query.include?("$1") && query !~ /limit \?/i
      end

      # removes comments
      # combines ?, ?, ? => ?
      def normalize_query(query)
        squish(query.to_s.gsub(/\?(, ?\?)+/, "?").gsub(/\/\*.+?\*\//, ""))
      end
    end
  end
end
