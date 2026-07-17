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
end
