require "json"
require "time"

module ActsAsMcp
  # Rack-compatible MCP endpoint: Streamable HTTP transport, stateless JSON
  # responses (the spec allows a plain application/json reply per request;
  # no SSE stream is opened). Zero gem dependencies — it only relies on the
  # Rack env contract, so anything Rack-compatible can mount it:
  #
  #   mount ActsAsMcp::Server.new => "/mcp"   # Rails routes.rb
  class Server
    PROTOCOL_VERSION = "2025-06-18".freeze
    JSON_HEADERS = { "content-type" => "application/json" }.freeze

    def call(env)
      return plain(405, "POST only") unless env["REQUEST_METHOD"] == "POST"

      message = parse(read_body(env))
      return rpc_error(nil, -32700, "Parse error") unless message.is_a?(Hash)

      id = message["id"]
      case message["method"]
      when "initialize" then rpc_result(id, initialize_result)
      when "notifications/initialized" then [202, JSON_HEADERS.dup, []]
      when "ping" then rpc_result(id, {})
      when "tools/list" then rpc_result(id, tools_list)
      when "tools/call" then tools_call(env, id, message["params"] || {})
      else rpc_error(id, -32601, "Method not found: #{message["method"].inspect}")
      end
    end

    private

    def read_body(env)
      input = env["rack.input"]
      input ? input.read.to_s : ""
    end

    def parse(raw)
      JSON.parse(raw)
    rescue JSON::ParserError
      nil
    end

    def initialize_result
      {
        "protocolVersion" => PROTOCOL_VERSION,
        "capabilities" => { "tools" => {} },
        "serverInfo" => {
          "name" => ActsAsMcp.config.server_name,
          "version" => ActsAsMcp.config.server_version,
        },
      }
    end

    def tools_list
      tools = ActsAsMcp.registry.tools.map do |tool|
        {
          "name" => tool.name,
          "description" => tool.description,
          "inputSchema" => tool.input_schema,
        }
      end
      { "tools" => tools }
    end

    def tools_call(env, id, params)
      name = params["name"].to_s
      args = params["arguments"] || {}
      tool = ActsAsMcp.registry.find(name)
      return rpc_error(id, -32602, "Unknown tool: #{name.inspect}") unless tool

      unless ActsAsMcp.config.authorize.call(env, name, args)
        audit(name, args, ok: false, error: "not authorized")
        return rpc_result(id, error_content("not authorized to call #{name}"))
      end

      started = clock_ms
      begin
        value = tool.handler.call(args)
        audit(name, args, ok: true, duration_ms: clock_ms - started)
        rpc_result(id, {
          "content" => [{ "type" => "text", "text" => JSON.generate(value) }],
          "isError" => false,
        })
      rescue ToolError => e
        audit(name, args, ok: false, duration_ms: clock_ms - started, error: e.message)
        rpc_result(id, error_content(e.message))
      rescue StandardError => e
        audit(name, args, ok: false, duration_ms: clock_ms - started,
                          error: "#{e.class}: #{e.message}")
        rpc_result(id, error_content("internal error in #{name}"))
      end
    end

    def error_content(text)
      { "content" => [{ "type" => "text", "text" => text }], "isError" => true }
    end

    def audit(tool, args, **fields)
      event = { tool: tool, args: args, at: Time.now.utc.iso8601 }.merge(fields)
      ActsAsMcp.config.audit_sink.call(event)
    rescue StandardError
      nil # an audit sink must never take the endpoint down
    end

    def clock_ms
      Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
    end

    def rpc_result(id, result)
      respond(200, { "jsonrpc" => "2.0", "id" => id, "result" => result })
    end

    def rpc_error(id, code, message)
      respond(200, { "jsonrpc" => "2.0", "id" => id, "error" => { "code" => code, "message" => message } })
    end

    def respond(status, payload)
      [status, JSON_HEADERS.dup, [JSON.generate(payload)]]
    end

    def plain(status, text)
      [status, { "content-type" => "text/plain" }, [text]]
    end
  end
end
