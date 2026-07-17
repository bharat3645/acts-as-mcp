module ActsAsMcp
  # Extend into an ActiveRecord model (or any class with a compatible query
  # interface: find_by / order / limit / offset, records with #attributes)
  # to register read-only MCP tools for it.
  #
  #   class Article < ApplicationRecord
  #     extend ActsAsMcp::Model
  #     acts_as_mcp expose: %i[id title body]
  #   end
  #
  # Read-only by design in v0.1: only `<model>_get` and `<model>_list` exist.
  # Only the attributes named in `expose:` ever leave the process.
  module Model
    def acts_as_mcp(expose:, description: nil, find: true, list: true)
      model = self
      exposed = Array(expose).map(&:to_s)
      raise ArgumentError, "acts_as_mcp requires expose: [...attribute names]" if exposed.empty?

      base = ActsAsMcp.tool_base_name(model.name)

      if find
        ActsAsMcp.registry.register(Tool.new(
          name: "#{base}_get",
          description: description || "Fetch one #{base} by primary key (read-only)",
          input_schema: {
            "type" => "object",
            "properties" => {
              "id" => { "type" => "integer", "description" => "primary key" },
            },
            "required" => ["id"],
          },
          handler: lambda do |args|
            record = model.find_by(model.primary_key => args["id"])
            raise ToolError, "#{base} #{args["id"].inspect} not found" unless record

            record.attributes.slice(*exposed)
          end
        ))
      end

      if list
        ActsAsMcp.registry.register(Tool.new(
          name: "#{base}_list",
          description: "List #{base} records (read-only, paginated)",
          input_schema: {
            "type" => "object",
            "properties" => {
              "limit" => { "type" => "integer", "minimum" => 1, "maximum" => 100 },
              "offset" => { "type" => "integer", "minimum" => 0 },
            },
          },
          handler: lambda do |args|
            limit = (args["limit"] || 25).to_i.clamp(1, 100)
            offset = [args["offset"].to_i, 0].max
            model.order(model.primary_key).limit(limit).offset(offset)
                 .map { |record| record.attributes.slice(*exposed) }
          end
        ))
      end

      nil
    end
  end

  # "Admin::BlogPost" -> "admin_blog_post" without an ActiveSupport dependency.
  def self.tool_base_name(class_name)
    class_name.gsub("::", "_")
              .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
              .gsub(/([a-z\d])([A-Z])/, '\1_\2')
              .downcase
  end
end
