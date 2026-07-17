module ActsAsMcp
  class Configuration
    # authorize: ->(rack_env, tool_name, arguments) { true | false }
    # audit_sink: ->(event_hash) { ... } — must never raise into the request
    attr_accessor :server_name, :server_version, :authorize, :audit_sink

    def initialize
      @server_name = "acts_as_mcp"
      @server_version = VERSION
      @authorize = ->(_env, _tool, _args) { true }
      @audit_sink = ->(_event) {}
    end
  end
end
