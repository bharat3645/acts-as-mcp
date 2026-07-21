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

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :articles, force: true do |t|
    t.string :title
    t.text :body
    t.string :internal_notes # deliberately NOT exposed below - see the response
  end
end

class Article < ActiveRecord::Base
  extend ActsAsMcp::Model
end

Article.acts_as_mcp(expose: %i[id title body])
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

puts "# acts_as_mcp registered these tools automatically from `expose:`:"
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
