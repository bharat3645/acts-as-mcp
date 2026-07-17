# acts_as_mcp

Expose a Rails app as a **policy-aware, read-only MCP server** — serve your
app *to* agents safely, instead of building agents in Ruby.

```ruby
# app/models/article.rb
class Article < ApplicationRecord
  extend ActsAsMcp::Model
  acts_as_mcp expose: %i[id title body]   # nothing else ever leaves
end

# config/routes.rb
mount ActsAsMcp::Server.new => "/mcp"
```

That's it: any MCP client (Claude, etc.) pointed at `https://yourapp/mcp`
now sees `article_get` and `article_list` tools — and only the attributes
you listed.

## Design decisions

- **Read-only by design (v0.1).** Only `_get` and `_list` tools exist.
  Write tools are a future, explicitly-opt-in surface.
- **Explicit exposure.** `expose:` is required; there is no "all attributes"
  default. Secret columns can't leak by omission.
- **Zero runtime dependencies.** The server implements the Rack env
  contract directly (Streamable HTTP transport, stateless JSON responses)
  — CI runs the core suite with *no gems installed* to keep this honest.
  Works with Rails, Sinatra, Hanami, plain `rackup`, anything Rack-shaped.
- **Per-call authorization hook.**

  ```ruby
  ActsAsMcp.configure do |c|
    c.authorize = ->(env, tool, args) { env["warden"]&.user&.admin? }
    c.audit_sink = ->(event) { McpAuditLog.create!(event) }
  end
  ```

  Denials return `isError` tool content and are audited like every call
  (tool, arguments, outcome, duration).
- **Expected failures are tool content, not protocol errors** (per MCP
  spec): a missing record is an `isError` result the model can read;
  unexpected exceptions are audited with class+message but reach the
  client only as a generic "internal error" (no stack/detail leakage).

## Protocol surface (v0.1)

`initialize` (protocol `2025-06-18`), `notifications/initialized` (202),
`ping`, `tools/list`, `tools/call`. Stateless JSON responses; no SSE
stream, no sessions — the spec's plain-JSON response mode.

## Testing

- `test/server_core_test.rb` — full endpoint behavior with hand-registered
  tools; runs with zero gems (`ruby -Ilib -Itest test/server_core_test.rb`).
- `test/model_test.rb` — ActiveRecord integration (sqlite3 in-memory):
  exposure filtering, pagination, clamping, not-found semantics.

## Roadmap

- v0.2: opt-in write tools with per-tool policies, AR-backed audit-log
  table + migration generator, Rails engine generators, `where:` filters
  with an allowlist.
- Rails engine class exists today but is a thin shim; mounting the Rack
  app is the supported path.

## License

MIT.
