module ActsAsMcp
  Tool = Struct.new(:name, :description, :input_schema, :handler)

  class Registry
    def initialize
      @tools = {}
    end

    def register(tool)
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
    end
  end
end
