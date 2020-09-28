require_relative "test_helper"

class SuggestedIndexesTest < Minitest::Test
  def setup
    database.reset_query_stats
  end

  def test_suggested_indexes_enabled
    assert database.suggested_indexes_enabled?
  end

  def test_basic
    User.where(email: "person1@example.org").first
    assert_equal [{table: "users", columns: ["email"]}], database.suggested_indexes.map { |q| q.except(:queries, :details) }
  end

  def test_hash
    query = "SELECT * FROM users WHERE login_attempts = 1"
    result = database.suggested_indexes_by_query(queries: [query])[query]
    assert_equal ["login_attempts"], result[:covering_index]
  end

  def test_existing_index
    User.where("updated_at > ?", Time.now).to_a
    assert_equal [], database.suggested_indexes.map { |q| q.except(:queries, :details) }
  end

  def test_gist_trgm
    query = "SELECT * FROM users WHERE country = 'Test 1'"
    result = database.suggested_indexes_by_query(queries: [query])[query]
    assert_nil result[:covering_index]
  end

  def test_ltree
    query = "SELECT * FROM users WHERE tree_path = 'path1'"
    result = database.suggested_indexes_by_query(queries: [query])[query]
    assert_equal ["tree_path"], result[:covering_index]
  end
end
