$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "acts_as_mcp"
require "minitest/autorun"
require "json"
require "stringio"

module McpTestHelpers
  # Drives the Rack app directly with a hand-built env — no rack gem needed,
  # which is exactly the zero-dependency contract the server promises.
  def post_rpc(server, payload)
    env = {
      "REQUEST_METHOD" => "POST",
      "rack.input" => StringIO.new(payload.is_a?(String) ? payload : JSON.generate(payload)),
    }
    status, headers, body = server.call(env)
    first = body.first
    parsed = first && !first.empty? ? JSON.parse(first) : nil
    [status, headers, parsed]
  end
end
