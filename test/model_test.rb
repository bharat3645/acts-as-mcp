require_relative "test_helper"
require "active_record"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :articles, force: true do |t|
    t.string :title
    t.text :body
    t.string :secret_token
  end
end

class Article < ActiveRecord::Base
  extend ActsAsMcp::Model
end

class ModelTest < Minitest::Test
  include McpTestHelpers

  def setup
    ActsAsMcp.reset!
    Article.acts_as_mcp(expose: %i[id title body])
    Article.delete_all
    @a1 = Article.create!(title: "Hello", body: "world", secret_token: "s3cr3t")
    @a2 = Article.create!(title: "Second", body: "post", secret_token: "hush")
    @server = ActsAsMcp::Server.new
  end

  def test_registers_read_only_tools_only
    assert_equal %w[article_get article_list], ActsAsMcp.registry.tools.map(&:name)
  end

  def test_get_returns_only_exposed_attributes
    _, _, msg = post_rpc(@server, { jsonrpc: "2.0", id: 1, method: "tools/call",
                                    params: { name: "article_get", arguments: { id: @a1.id } } })
    payload = JSON.parse(msg["result"]["content"].first["text"])
    assert_equal "Hello", payload["title"]
    assert_equal @a1.id, payload["id"]
    refute payload.key?("secret_token")
  end

  def test_get_missing_record_is_tool_error
    _, _, msg = post_rpc(@server, { jsonrpc: "2.0", id: 2, method: "tools/call",
                                    params: { name: "article_get", arguments: { id: 999_999 } } })
    assert msg["result"]["isError"]
    assert_match(/not found/, msg["result"]["content"].first["text"])
  end

  def test_list_pagination_and_exposure
    _, _, msg = post_rpc(@server, { jsonrpc: "2.0", id: 3, method: "tools/call",
                                    params: { name: "article_list", arguments: { limit: 1, offset: 1 } } })
    rows = JSON.parse(msg["result"]["content"].first["text"])
    assert_equal 1, rows.size
    assert_equal "Second", rows.first["title"]
    refute rows.first.key?("secret_token")
  end

  def test_list_limit_is_clamped
    _, _, msg = post_rpc(@server, { jsonrpc: "2.0", id: 4, method: "tools/call",
                                    params: { name: "article_list", arguments: { limit: 10_000 } } })
    rows = JSON.parse(msg["result"]["content"].first["text"])
    assert_equal 2, rows.size
  end

  def test_expose_is_required
    assert_raises(ArgumentError) { Article.acts_as_mcp(expose: []) }
  end

  def test_where_must_be_subset_of_expose
    err = assert_raises(ArgumentError) do
      Article.acts_as_mcp(expose: %i[id title], where: %i[secret_token])
    end
    assert_match(/secret_token/, err.message)
    assert_match(/expose:/, err.message)
  end

  def test_list_without_where_declared_has_no_where_property
    Article.acts_as_mcp(expose: %i[id title body])
    tool = ActsAsMcp.registry.find("article_list")
    refute tool.input_schema["properties"].key?("where")
  end

  def test_list_filters_on_allowlisted_attribute
    Article.acts_as_mcp(expose: %i[id title body], where: %i[title])
    tool = ActsAsMcp.registry.find("article_list")
    assert_equal %w[title], tool.input_schema["properties"]["where"]["properties"].keys

    _, _, msg = post_rpc(@server, { jsonrpc: "2.0", id: 5, method: "tools/call",
                                    params: { name: "article_list",
                                              arguments: { where: { title: "Second" } } } })
    rows = JSON.parse(msg["result"]["content"].first["text"])
    assert_equal 1, rows.size
    assert_equal "Second", rows.first["title"]
    refute rows.first.key?("secret_token")
  end

  def test_list_filter_combines_with_pagination
    Article.acts_as_mcp(expose: %i[id title body], where: %i[body])
    3.times { |i| Article.create!(title: "Match #{i}", body: "shared", secret_token: "x") }
    _, _, msg = post_rpc(@server, { jsonrpc: "2.0", id: 6, method: "tools/call",
                                    params: { name: "article_list",
                                              arguments: { where: { body: "shared" }, limit: 2 } } })
    rows = JSON.parse(msg["result"]["content"].first["text"])
    assert_equal 2, rows.size
  end

  def test_list_rejects_disallowed_filter_key
    Article.acts_as_mcp(expose: %i[id title body], where: %i[title])
    _, _, msg = post_rpc(@server, { jsonrpc: "2.0", id: 7, method: "tools/call",
                                    params: { name: "article_list",
                                              arguments: { where: { body: "world" } } } })
    assert msg["result"]["isError"]
    assert_match(/not a filterable attribute/, msg["result"]["content"].first["text"])
    assert_match(/title/, msg["result"]["content"].first["text"])
  end

  def test_list_rejects_filter_on_non_exposed_column_even_if_column_exists
    Article.acts_as_mcp(expose: %i[id title body], where: %i[title])
    _, _, msg = post_rpc(@server, { jsonrpc: "2.0", id: 8, method: "tools/call",
                                    params: { name: "article_list",
                                              arguments: { where: { secret_token: "s3cr3t" } } } })
    assert msg["result"]["isError"]
    assert_match(/not a filterable attribute/, msg["result"]["content"].first["text"])
  end

  def test_list_rejects_non_object_where
    Article.acts_as_mcp(expose: %i[id title body], where: %i[title])
    _, _, msg = post_rpc(@server, { jsonrpc: "2.0", id: 9, method: "tools/call",
                                    params: { name: "article_list", arguments: { where: "Hello" } } })
    assert msg["result"]["isError"]
    assert_match(/must be an object/, msg["result"]["content"].first["text"])
  end

  def test_list_rejects_non_scalar_filter_value
    Article.acts_as_mcp(expose: %i[id title body], where: %i[title])
    _, _, msg = post_rpc(@server, { jsonrpc: "2.0", id: 10, method: "tools/call",
                                    params: { name: "article_list",
                                              arguments: { where: { title: { "$ne" => "x" } } } } })
    assert msg["result"]["isError"]
    assert_match(/must be a string\/number\/bool\/null/, msg["result"]["content"].first["text"])
  end

  def test_list_no_where_argument_still_returns_everything
    Article.acts_as_mcp(expose: %i[id title body], where: %i[title])
    _, _, msg = post_rpc(@server, { jsonrpc: "2.0", id: 11, method: "tools/call",
                                    params: { name: "article_list", arguments: {} } })
    rows = JSON.parse(msg["result"]["content"].first["text"])
    assert_equal 2, rows.size
  end
end
