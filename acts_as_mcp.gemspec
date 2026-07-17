require_relative "lib/acts_as_mcp/version"

Gem::Specification.new do |spec|
  spec.name = "acts_as_mcp"
  spec.version = ActsAsMcp::VERSION
  spec.authors = ["Bharat Singh Parihar"]
  spec.email = ["145659423+bharat3645@users.noreply.github.com"]

  spec.summary = "Expose a Rails app as a policy-aware, read-only MCP server"
  spec.description = "Mount a zero-dependency Rack endpoint that serves your ActiveRecord " \
                     "models as Model Context Protocol tools: explicit attribute exposure, " \
                     "read-only defaults, a per-call authorization hook, and audit events."
  spec.homepage = "https://github.com/bharat3645/acts-as-mcp"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "README.md", "CHANGELOG.md", "LICENSE"]
  spec.require_paths = ["lib"]
end
