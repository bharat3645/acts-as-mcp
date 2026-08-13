require_relative "test_helper"

# ActiveRecord-free suite: exercises the whole MCP endpoint against
# hand-registered tools. Runs anywhere plain Ruby runs.
class ServerCoreTest < Minitest::Test
  include McpTestHelpers

  def setup
    ActsAsMcp.reset!
    ActsAsMcp.registry.register(ActsAsMcp::Tool.new(
      name: "echo",
      description: "echo back",
      input_schema: {"type" => "object"},
      handler: ->(args) { {"echo" => args} }
    ))
    ActsAsMcp.registry.register(ActsAsMcp::Tool.new(
      name: "boom",
      description: "always fails (expected failure path)",
      input_schema: {"type" => "object"},
      handler: ->(_args) { raise ActsAsMcp::ToolError, "kaput" }
    ))
    ActsAsMcp.registry.register(ActsAsMcp::Tool.new(
      name: "crash",
      description: "unexpected exception path",
      input_schema: {"type" => "object"},
      handler: ->(_args) { raise "grubby internals: /etc/passwd" }
    ))
    @server = ActsAsMcp::Server.new
  end

  def test_rejects_non_post
    status, = @server.call({"REQUEST_METHOD" => "GET"})
    assert_equal 405, status
  end

  def test_parse_error
    _, _, msg = post_rpc(@server, "{nope")
    assert_equal(-32700, msg["error"]["code"])
  end

  def test_initialize_shape
    _, headers, msg = post_rpc(@server, {jsonrpc: "2.0", id: 1, method: "initialize", params: {}})
    assert_equal "application/json", headers["content-type"]
    result = msg["result"]
    assert_equal ActsAsMcp::Server::PROTOCOL_VERSION, result["protocolVersion"]
    assert_equal "acts_as_mcp", result["serverInfo"]["name"]
    assert result["capabilities"].key?("tools")
  end

  def test_initialized_notification_gets_202
    status, _, msg = post_rpc(@server, {jsonrpc: "2.0", method: "notifications/initialized"})
    assert_equal 202, status
    assert_nil msg
  end

  def test_ping
    _, _, msg = post_rpc(@server, {jsonrpc: "2.0", id: 9, method: "ping"})
    assert_equal({}, msg["result"])
  end

  def test_tools_list_sorted_with_schemas
    _, _, msg = post_rpc(@server, {jsonrpc: "2.0", id: 2, method: "tools/list"})
    names = msg["result"]["tools"].map { |t| t["name"] }
    assert_equal %w[boom crash echo], names
    assert(msg["result"]["tools"].all? { |t| t.key?("inputSchema") })
  end

  def test_tools_call_success_and_audit_event
    events = []
    ActsAsMcp.config.audit_sink = ->(event) { events << event }
    _, _, msg = post_rpc(@server, {jsonrpc: "2.0", id: 3, method: "tools/call",
                                    params: {name: "echo", arguments: {"x" => 1}}})
    result = msg["result"]
    refute result["isError"]
    assert_equal({"echo" => {"x" => 1}}, JSON.parse(result["content"].first["text"]))
    assert_equal 1, events.size
    assert_equal "echo", events.first[:tool]
    assert events.first[:ok]
    assert events.first.key?(:duration_ms)
  end

  def test_tool_error_is_iserror_content_not_protocol_error
    _, _, msg = post_rpc(@server, {jsonrpc: "2.0", id: 4, method: "tools/call",
                                    params: {name: "boom", arguments: {}}})
    assert msg["result"]["isError"]
    assert_match(/kaput/, msg["result"]["content"].first["text"])
  end

  def test_unexpected_exception_is_not_leaked
    _, _, msg = post_rpc(@server, {jsonrpc: "2.0", id: 5, method: "tools/call",
                                    params: {name: "crash", arguments: {}}})
    assert msg["result"]["isError"]
    text = msg["result"]["content"].first["text"]
    refute_match(/passwd/, text)
    assert_match(/internal error/, text)
  end

  def test_unknown_tool
    _, _, msg = post_rpc(@server, {jsonrpc: "2.0", id: 6, method: "tools/call", params: {name: "nope"}})
    assert_equal(-32602, msg["error"]["code"])
  end

  def test_unknown_method
    _, _, msg = post_rpc(@server, {jsonrpc: "2.0", id: 7, method: "wat"})
    assert_equal(-32601, msg["error"]["code"])
  end

  def test_authorization_denial_is_audited
    events = []
    ActsAsMcp.config.audit_sink = ->(event) { events << event }
    ActsAsMcp.config.authorize = ->(_env, tool, _args) { tool != "echo" }
    _, _, msg = post_rpc(@server, {jsonrpc: "2.0", id: 8, method: "tools/call",
                                    params: {name: "echo", arguments: {}}})
    assert msg["result"]["isError"]
    assert_match(/not authorized/, msg["result"]["content"].first["text"])
    assert_equal [false], events.map { |e| e[:ok] }
  end

  def test_audit_sink_failure_does_not_break_the_call
    ActsAsMcp.config.audit_sink = ->(_event) { raise "sink broken" }
    _, _, msg = post_rpc(@server, {jsonrpc: "2.0", id: 10, method: "tools/call",
                                    params: {name: "echo", arguments: {}}})
    refute msg["result"]["isError"]
  end

  def test_tool_base_name
    assert_equal "blog_post", ActsAsMcp.tool_base_name("BlogPost")
    assert_equal "admin_blog_post", ActsAsMcp.tool_base_name("Admin::BlogPost")
    assert_equal "api_key", ActsAsMcp.tool_base_name("APIKey")
  end
end
