# frozen_string_literal: true

# Real, runnable example of the gem's other flagship feature:
# `ActiveRecord::Base.acts_as_mcp` exposing a model as read-only MCP
# tools. Needs the activerecord and sqlite3 gems (dev-only - the gem
# itself has zero runtime dependencies; this is an example, not part of
# what ships):
#
#   gem install activerecord sqlite3
#   ruby -Ilib examples/activerecord_model.rb

require "acts_as_mcp"
require "active_record"
require "json"
require "stringio"

# acts_as_mcp.rb only conditionally requires audit_log.rb if
# ActiveRecord is already loaded at that moment - here "acts_as_mcp" was
# required above, before "active_record", so it's pulled in explicitly
# (a real Rails app doesn't hit this: Bundler.require runs after
# `require "rails/all"`, so ActiveRecord::Base already exists).
require_relative "../lib/acts_as_mcp/audit_log"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :articles, force: true do |t|
    t.string :title
    t.text :body
    t.string :internal_notes # deliberately NOT exposed below - see the response
  end

  create_table :acts_as_mcp_audit_logs, force: true do |t|
    t.string :tool, null: false
    t.text :args
    t.boolean :ok, null: false
    t.integer :duration_ms
    t.text :error
    t.datetime :occurred_at, null: false
    t.timestamps
  end
end

class Article < ActiveRecord::Base
  extend ActsAsMcp::Model
end

Article.acts_as_mcp(expose: %i[id title body], where: %i[title])
ActsAsMcp.configure { |c| c.audit_sink = ActsAsMcp::ActiveRecordAuditSink.new }
Article.create!(title: "Shipping idempotent_rack", body: "Idempotency-Key middleware for Rack.",
                 internal_notes: "unpublished draft, do not expose")
Article.create!(title: "Shipping modelgate", body: "A multi-provider LLM gateway.",
                 internal_notes: "unpublished draft, do not expose")

server = ActsAsMcp::Server.new

def send_rpc(server, payload)
  puts "--> #{JSON.generate(payload)}"
  env = { "REQUEST_METHOD" => "POST", "rack.input" => StringIO.new(JSON.generate(payload)) }
  _status, _headers, body = server.call(env)
  puts "<-- #{body.first}"
  puts
end

puts "# acts_as_mcp registered these tools automatically from `expose:` + `where:`:"
send_rpc(server, { jsonrpc: "2.0", id: 1, method: "tools/list" })

puts "# article_list - note internal_notes never appears, it was never exposed:"
send_rpc(server, { jsonrpc: "2.0", id: 2, method: "tools/call",
                    params: { name: "article_list", arguments: { limit: 10 } } })

puts "# article_get for a specific id:"
send_rpc(server, { jsonrpc: "2.0", id: 3, method: "tools/call",
                    params: { name: "article_get", arguments: { id: Article.first.id } } })

puts "# article_get for a missing id - a real ToolError, not a 500 or a nil crash:"
send_rpc(server, { jsonrpc: "2.0", id: 4, method: "tools/call",
                    params: { name: "article_get", arguments: { id: 999_999 } } })

puts "# article_list filtered by an allowlisted `where:` attribute (exact match):"
send_rpc(server, { jsonrpc: "2.0", id: 5, method: "tools/call",
                    params: { name: "article_list",
                              arguments: { where: { title: "Shipping modelgate" } } } })

puts "# filtering on internal_notes is rejected - it's not in where:, even though it exists:"
send_rpc(server, { jsonrpc: "2.0", id: 6, method: "tools/call",
                    params: { name: "article_list",
                              arguments: { where: { internal_notes: "unpublished draft, do not expose" } } } })

puts "# every call above was persisted by ActsAsMcp::ActiveRecordAuditSink " \
     "(rails generate acts_as_mcp:audit_log for the migration) - real rows, not a mock:"
ActsAsMcp::AuditLog.order(:id).each do |log|
  puts "  ##{log.id} tool=#{log.tool.inspect} ok=#{log.ok} args=#{log.args} " \
       "duration_ms=#{log.duration_ms.inspect} error=#{log.error.inspect}"
end
