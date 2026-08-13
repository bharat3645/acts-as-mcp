require "active_record"
require_relative "test_helper"
require_relative "../lib/acts_as_mcp/audit_log"
require "minitest/mock"

# ActsAsMcp::AuditLog gets its OWN connection (rather than
# ActiveRecord::Base.establish_connection) so this file's schema setup
# can't race model_test.rb's - `rake test` loads every *_test.rb into one
# process, and two files both re-establishing ActiveRecord::Base's shared
# :memory: connection at file-load time is a real, load-order-dependent
# collision (whichever runs establish_connection last silently wipes out
# the other's tables). Scoping the connection to the AuditLog class keeps
# each model's schema in its own isolated in-memory database.
ActsAsMcp::AuditLog.establish_connection(adapter: "sqlite3", database: ":memory:")
ActsAsMcp::AuditLog.connection.create_table :acts_as_mcp_audit_logs, force: true do |t|
  t.string :tool, null: false
  t.text :args
  t.boolean :ok, null: false
  t.integer :duration_ms
  t.text :error
  t.datetime :occurred_at, null: false
  t.timestamps
end

class AuditLogTest < Minitest::Test
  include McpTestHelpers

  def setup
    ActsAsMcp.reset!
    ActsAsMcp::AuditLog.delete_all
    ActsAsMcp.registry.register(ActsAsMcp::Tool.new(
      name: "echo",
      description: "echo back",
      input_schema: { "type" => "object" },
      handler: ->(args) { { "echo" => args } }
    ))
    ActsAsMcp.registry.register(ActsAsMcp::Tool.new(
      name: "boom",
      description: "always fails (expected failure path)",
      input_schema: { "type" => "object" },
      handler: ->(_args) { raise ActsAsMcp::ToolError, "kaput" }
    ))
    ActsAsMcp.config.audit_sink = ActsAsMcp::ActiveRecordAuditSink.new
    @server = ActsAsMcp::Server.new
  end

  def test_successful_call_is_persisted
    post_rpc(@server, { jsonrpc: "2.0", id: 1, method: "tools/call",
                         params: { name: "echo", arguments: { "city" => "Austin" } } })
    log = ActsAsMcp::AuditLog.last
    assert_equal "echo", log.tool
    assert log.ok
    assert_nil log.error
    assert_kind_of Integer, log.duration_ms
    assert_equal({ "city" => "Austin" }, JSON.parse(log.args))
    assert (Time.now.utc - log.occurred_at).abs < 5
  end

  def test_tool_error_is_persisted_with_ok_false_and_error_message
    post_rpc(@server, { jsonrpc: "2.0", id: 2, method: "tools/call",
                         params: { name: "boom", arguments: {} } })
    log = ActsAsMcp::AuditLog.last
    assert_equal "boom", log.tool
    refute log.ok
    assert_equal "kaput", log.error
  end

  def test_authorization_denial_is_persisted_without_a_duration
    ActsAsMcp.config.authorize = ->(_env, _tool, _args) { false }
    post_rpc(@server, { jsonrpc: "2.0", id: 3, method: "tools/call",
                         params: { name: "echo", arguments: {} } })
    log = ActsAsMcp::AuditLog.last
    refute log.ok
    assert_equal "not authorized", log.error
    assert_nil log.duration_ms
  end

  def test_multiple_calls_accumulate_independent_rows
    post_rpc(@server, { jsonrpc: "2.0", id: 4, method: "tools/call",
                         params: { name: "echo", arguments: { "a" => 1 } } })
    post_rpc(@server, { jsonrpc: "2.0", id: 5, method: "tools/call",
                         params: { name: "echo", arguments: { "a" => 2 } } })
    assert_equal 2, ActsAsMcp::AuditLog.count
  end

  def test_sink_never_raises_into_the_request_when_persistence_fails
    ActsAsMcp::AuditLog.stub(:create!, ->(*) { raise "db unavailable" }) do
      status, _headers, msg = post_rpc(@server, { jsonrpc: "2.0", id: 6, method: "tools/call",
                                                   params: { name: "echo", arguments: {} } })
      assert_equal 200, status
      refute msg["result"]["isError"]
    end
    assert_equal 0, ActsAsMcp::AuditLog.count
  end
end
