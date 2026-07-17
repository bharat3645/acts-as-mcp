require_relative "acts_as_mcp/version"
require_relative "acts_as_mcp/errors"
require_relative "acts_as_mcp/configuration"
require_relative "acts_as_mcp/registry"
require_relative "acts_as_mcp/model"
require_relative "acts_as_mcp/server"
require_relative "acts_as_mcp/engine" if defined?(::Rails::Engine)

module ActsAsMcp
  def self.config
    @config ||= Configuration.new
  end

  def self.configure
    yield config
  end

  def self.registry
    @registry ||= Registry.new
  end

  # Test helper / full reset of global state.
  def self.reset!
    @config = Configuration.new
    @registry = Registry.new
  end
end
