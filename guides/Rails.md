# PgHero for Rails

:gem:

## Installation

Add this line to your application’s Gemfile:

```ruby
gem 'pghero'
```

And mount the dashboard in your `config/routes.rb`:

```ruby
mount PgHero::Engine, at: "pghero"
```

Be sure to [secure the dashboard](#security) in production.

## Insights

```ruby
PgHero.running_queries
PgHero.long_running_queries
PgHero.index_usage
PgHero.missing_indexes
PgHero.unused_indexes
PgHero.unused_tables
PgHero.database_size
PgHero.relation_sizes
PgHero.index_hit_rate
PgHero.table_hit_rate
PgHero.total_connections
```

Kill queries

```ruby
PgHero.kill(pid)
PgHero.kill_long_running_queries # [master]
PgHero.kill_all
```

Query stats

```ruby
PgHero.query_stats_enabled?
PgHero.enable_query_stats
PgHero.disable_query_stats
PgHero.reset_query_stats
PgHero.query_stats
PgHero.slow_queries
```

Security [master]

```ruby
PgHero.ssl_used?
```

Replication [master]

```ruby
PgHero.replica?
PgHero.replication_lag
```

## Users

Create a user

```ruby
PgHero.create_user("link")
# {password: "zbTrNHk2tvMgNabFgCo0ws7T"}
```

This generates and returns a secure password.  The user has full access to the `public` schema.

Read-only access

```ruby
PgHero.create_user("epona", readonly: true)
```

Set the password

```ruby
PgHero.create_user("zelda", password: "hyrule")
```

Drop a user

```ruby
PgHero.drop_user("ganondorf")
```

## Security

#### Basic Authentication

Set the following variables in your environment or an initializer.

```ruby
ENV["PGHERO_USERNAME"] = "link"
ENV["PGHERO_PASSWORD"] = "hyrule"
```

#### Devise

```ruby
authenticate :user, lambda { |user| user.admin? } do
  mount PgHero::Engine, at: "pghero"
end
```

## Query Stats

Query stats can be enabled from the dashboard. If you run into issues, [view the guide](Query-Stats.md).

## System Stats

CPU usage is available for Amazon RDS.  Add these lines to your application’s Gemfile:

```ruby
gem 'aws-sdk'
gem 'chartkick'
```

And add these variables to your environment:

```sh
PGHERO_ACCESS_KEY_ID=accesskey123
PGHERO_SECRET_ACCESS_KEY=secret123
PGHERO_DB_INSTANCE_IDENTIFIER=epona
```

## Multiple Databases [master]

Create `config/pghero.yml` with:

```yml
default: &default
  databases:
    primary:
      url: <%= ENV["PGHERO_DATABASE_URL"] %>
    replica:
      url: <%= ENV["REPLICA_DATABASE_URL"] %>

development:
  <<: *default

production:
  <<: *default
```

## Customize

Minimum time for long running queries

```ruby
PgHero.long_running_query_sec = 60 # default
```

Minimum average time for slow queries

```ruby
PgHero.slow_query_ms = 20 # default
```

Minimum calls for slow queries

```ruby
PgHero.slow_query_calls = 100 # default
```

Minimum connections for high connections warning

```ruby
PgHero.total_connections_threshold = 100 # default
```

## Bonus

- See where queries come from with [Marginalia](https://github.com/basecamp/marginalia) - comments appear on the Live Queries tab.
- Get weekly news and articles with [Postgres Weekly](http://postgresweekly.com)
- Optimize your configuration with [PgTune](http://pgtune.leopard.in.ua) and [pgBench](http://www.postgresql.org/docs/devel/static/pgbench.html)