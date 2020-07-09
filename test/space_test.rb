require_relative "test_helper"

class SpaceTest < Minitest::Test
  def test_database_size
    assert database.database_size
  end

  def test_relation_sizes
    assert database.relation_sizes
  end

  def test_table_sizes
    assert database.table_sizes
  end

  def test_space_growth
    assert database.space_growth
  end

  def test_relation_space_stats
    assert database.relation_space_stats("cities")
  end

  def test_capture_space_stats
    PgHero::SpaceStats.delete_all
    refute PgHero::SpaceStats.any?
    assert database.capture_space_stats
    assert PgHero::SpaceStats.any?
  end

  def test_clean_space_stats
    assert database.clean_space_stats
  end

  def test_space_stats_enabled
    assert database.space_stats_enabled?
  end
end
