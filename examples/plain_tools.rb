# frozen_string_literal: true

# Real, runnable example: hand-registered tools (no ActiveRecord, no Rails,
# no Rack gem) driving a full initialize -> tools/list -> tools/call
# sequence against the real Server class, printing the real JSON-RPC
# request/response on the wire. This is exactly what
# `ruby -Ilib examples/plain_tools.rb` produces - not hand-written sample
# output.
#
#   ruby -Ilib examples/plain_tools.rb

require "acts_as_mcp"
require "json"
require "stringio"

ActsAsMcp.registry.register(ActsAsMcp::Tool.new(
  name: "weather_lookup",
  description: "Look up the current weather for a city.",
  input_schema: {"type" => "object", "properties" => {"city" => {"type" => "string"}}, "required" => ["city"]},
  handler: ->(args) {
    # A real tool would call a real weather API. This one's fake, on purpose -
    # the point of this example is the MCP wire protocol, not weather data.
    {"city" => args.fetch("city"), "condition" => "sunny", "temp_f" => 72}
  }
))

ActsAsMcp.registry.register(ActsAsMcp::Tool.new(
  name: "divide",
  description: "Divide two numbers.",
  input_schema: {"type" => "object", "properties" => {"a" => {"type" => "number"}, "b" => {"type" => "number"}}},
  handler: ->(args) {
    raise ActsAsMcp::ToolError, "cannot divide by zero" if args["b"].to_f.zero?

    {"result" => args.fetch("a").to_f / args.fetch("b").to_f}
  }
))

server = ActsAsMcp::Server.new

def send_rpc(server, payload)
  puts "--> #{JSON.generate(payload)}"
  env = {"REQUEST_METHOD" => "POST", "rack.input" => StringIO.new(JSON.generate(payload))}
  _status, _headers, body = server.call(env)
  response = body.first
  puts "<-- #{response}" unless response.nil? || response.empty?
  puts
end

send_rpc(server, {jsonrpc: "2.0", id: 1, method: "initialize", params: {}})
send_rpc(server, {jsonrpc: "2.0", id: 2, method: "tools/list"})
send_rpc(server, {jsonrpc: "2.0", id: 3, method: "tools/call",
                    params: {name: "weather_lookup", arguments: {city: "Austin"}}})
puts "# Calling divide with b: 0 - a real ToolError, not a crash:"
send_rpc(server, {jsonrpc: "2.0", id: 4, method: "tools/call",
                    params: {name: "divide", arguments: {a: 10, b: 0}}})
puts "# Calling an unregistered tool - JSON-RPC -32602, not a 500:"
send_rpc(server, {jsonrpc: "2.0", id: 5, method: "tools/call",
                    params: {name: "nonexistent_tool", arguments: {}}})
