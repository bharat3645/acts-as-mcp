module ActsAsMcp
  # Optional Rails integration. Mounting works without this file —
  # `mount ActsAsMcp::Server.new => "/mcp"` is plain Rack — but requiring
  # the gem inside a Rails app also defines an engine so conventional
  # initializer ordering applies.
  class Engine < ::Rails::Engine
    isolate_namespace ActsAsMcp
  end
end
