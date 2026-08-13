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
    # where: is an explicit allowlist of attributes the generated `_list`
    # tool may be filtered on (exact match only). Same "explicit, no
    # default-open surface" discipline as expose: - every filterable
    # attribute must ALSO be in expose: (you can only search on a column
    # the caller can already see; filtering on a hidden column would let a
    # model probe its value indirectly via presence/absence of matches,
    # a real side channel even though the value itself never appears in a
    # response).
    def acts_as_mcp(expose:, description: nil, find: true, list: true, where: [])
      model = self
      exposed = Array(expose).map(&:to_s)
      raise ArgumentError, "acts_as_mcp requires expose: [...attribute names]" if exposed.empty?

      filterable = Array(where).map(&:to_s)
      leaked = filterable - exposed
      unless leaked.empty?
        raise ArgumentError,
          "acts_as_mcp where: #{leaked.inspect} must also be listed in expose: " \
          "(filtering on a non-exposed attribute is a side channel)"
      end

      base = ActsAsMcp.tool_base_name(model.name)

      if find
        ActsAsMcp.registry.register(Tool.new(
          name: "#{base}_get",
          description: description || "Fetch one #{base} by primary key (read-only)",
          input_schema: {
            "type" => "object",
            "properties" => {
              "id" => {"type" => "integer", "description" => "primary key"}
            },
            "required" => ["id"]
          },
          handler: lambda do |args|
            record = model.find_by(model.primary_key => args["id"])
            raise ToolError, "#{base} #{args["id"].inspect} not found" unless record

            record.attributes.slice(*exposed)
          end
        ))
      end

      if list
        list_properties = {
          "limit" => {"type" => "integer", "minimum" => 1, "maximum" => 100},
          "offset" => {"type" => "integer", "minimum" => 0}
        }
        unless filterable.empty?
          list_properties["where"] = {
            "type" => "object",
            "description" => "Exact-match filters. Allowed keys: #{filterable.join(", ")}.",
            "additionalProperties" => false,
            "properties" => filterable.to_h { |f| [f, {"type" => %w[string integer number boolean null]}] }
          }
        end

        ActsAsMcp.registry.register(Tool.new(
          name: "#{base}_list",
          description: "List #{base} records (read-only, paginated" \
                       "#{", filterable on #{filterable.join(", ")}" unless filterable.empty?})",
          input_schema: {
            "type" => "object",
            "properties" => list_properties
          },
          handler: lambda do |args|
            limit = (args["limit"] || 25).to_i.clamp(1, 100)
            offset = [args["offset"].to_i, 0].max
            scope = model.order(model.primary_key)

            if args.key?("where") && !args["where"].nil?
              raw = args["where"]
              raise ToolError, "where: must be an object" unless raw.is_a?(Hash)

              conditions = {}
              raw.each do |key, value|
                key = key.to_s
                unless filterable.include?(key)
                  raise ToolError, "where: #{key.inspect} is not a filterable attribute " \
                                    "(allowed: #{filterable.join(", ")})"
                end
                unless value.nil? || value.is_a?(String) || value.is_a?(Numeric) ||
                       value == true || value == false
                  raise ToolError, "where: #{key.inspect} must be a string/number/bool/null, " \
                                    "got #{value.class}"
                end
                conditions[key] = value
              end
              scope = scope.where(conditions) unless conditions.empty?
            end

            scope.limit(limit).offset(offset)
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
