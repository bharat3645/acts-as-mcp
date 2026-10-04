module ActsAsMcp
  Tool = Struct.new(:name, :description, :input_schema, :handler)

  class Registry
    def initialize
      @tools = {}
      @sources = {}
    end

    # source: an opaque string identifying what registered this tool name
    # (acts_as_mcp passes the model's class name). Re-registering under the
    # SAME source is allowed and silently replaces the old tool - this is
    # what makes Rails class reloading in development work, since
    # `acts_as_mcp` re-runs for the same model on every reload. Registering
    # the same tool name under a DIFFERENT source raises instead of
    # silently overwriting: `tool_base_name` decamelizes without
    # namespacing, so two distinct classes (e.g. `Admin::BlogPost` and
    # `AdminBlog::Post`) can map to the identical base name, and without
    # this check one model's tool would silently vanish or start serving
    # the other model's data with no error at all.
    def register(tool, source: nil)
      existing_source = @sources[tool.name]
      if source && existing_source && existing_source != source
        raise ArgumentError,
          "acts_as_mcp: tool #{tool.name.inspect} is already registered by " \
          "#{existing_source}, but #{source} also decamelizes to the same " \
          "base name. Rename one of the models - acts_as_mcp does not " \
          "namespace tool names."
      end
      @sources[tool.name] = source if source
      @tools[tool.name] = tool
      tool
    end

    def find(name)
      @tools[name]
    end

    def tools
      @tools.values.sort_by(&:name)
    end

    def clear!
      @tools = {}
      @sources = {}
    end
  end
end
