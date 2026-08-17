# acts_as_mcp

[![CI](https://github.com/bharat3645/acts-as-mcp/actions/workflows/ci.yml/badge.svg)](https://github.com/bharat3645/acts-as-mcp/actions/workflows/ci.yml)

Expose a Rails app as a **policy-aware, read-only MCP server** — serve your
app *to* agents safely, instead of building agents in Ruby.

> **Read-only by design:** v0.1/v0.2 intentionally ship only `_get`/`_list`
> tools — there is no write surface yet. This is a deliberate safety
> default, not a missing feature; see [Design decisions](#design-decisions)
> below for the reasoning, and the [Roadmap](#roadmap) for opt-in write
> tools.

## Installation

Add this line to your application's Gemfile:

```ruby
gem "acts_as_mcp"
```

And then run:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install acts_as_mcp
```

## Usage

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
  (tool, arguments, outcome, duration). `audit_sink` can be any callable
  - `ActsAsMcp::ActiveRecordAuditSink` below is a ready-made one if you'd
  rather not write `McpAuditLog` yourself.
- **Expected failures are tool content, not protocol errors** (per MCP
  spec): a missing record is an `isError` result the model can read;
  unexpected exceptions are audited with class+message but reach the
  client only as a generic "internal error" (no stack/detail leakage).

## Example: the real wire protocol

`examples/plain_tools.rb` registers two tools by hand (no ActiveRecord,
no Rails) and drives a real `initialize` -> `tools/list` -> `tools/call`
sequence against the real `Server` class. Real, unedited output
(`ruby -Ilib examples/plain_tools.rb`):

```
--> {"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
<-- {"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","capabilities":{"tools":{}},"serverInfo":{"name":"acts_as_mcp","version":"0.1.0"}}}

--> {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"weather_lookup","arguments":{"city":"Austin"}}}
<-- {"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"{\"city\":\"Austin\",\"condition\":\"sunny\",\"temp_f\":72}"}],"isError":false}}

# Calling divide with b: 0 - a real ToolError, not a crash:
--> {"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"divide","arguments":{"a":10,"b":0}}}
<-- {"jsonrpc":"2.0","id":4,"result":{"content":[{"type":"text","text":"cannot divide by zero"}],"isError":true}}
```

`examples/activerecord_model.rb` is the same idea for the `expose:`
feature - real output showing `internal_notes` never appearing anywhere,
because it was never listed in `expose:` (needs `gem install activerecord
sqlite3`, dev-only - the gem itself stays zero-dependency):

```
# article_list - note internal_notes never appears, it was never exposed:
--> {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"article_list","arguments":{"limit":10}}}
<-- {"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"[{\"id\":1,\"title\":\"Shipping idempotent_rack\",\"body\":\"Idempotency-Key middleware for Rack.\"},{\"id\":2,\"title\":\"Shipping modelgate\",\"body\":\"A multi-provider LLM gateway.\"}]"}],"isError":false}}
```

## Filtering `_list` with `where:`

`_list` can take an optional `where:` allowlist of attributes the caller
may filter on (exact match only). Same discipline as `expose:` - nothing
is filterable by default, and a filterable attribute must **also** be
exposed (filtering on a hidden column would let a model probe its value
indirectly via presence/absence of matches, even though the value itself
never appears in a response):

```ruby
Article.acts_as_mcp(expose: %i[id title body], where: %i[title])
```

Real captured output - filtering works on the allowlisted attribute,
and is rejected (as a `ToolError`, not a crash or a silent no-op) for
anything not on the list, even a real column that happens to exist:

```
# article_list filtered by an allowlisted `where:` attribute (exact match):
--> {"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"article_list","arguments":{"where":{"title":"Shipping modelgate"}}}}
<-- {"jsonrpc":"2.0","id":5,"result":{"content":[{"type":"text","text":"[{\"id\":2,\"title\":\"Shipping modelgate\",\"body\":\"A multi-provider LLM gateway.\"}]"}],"isError":false}}

# filtering on internal_notes is rejected - it's not in where:, even though it exists:
--> {"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"article_list","arguments":{"where":{"internal_notes":"unpublished draft, do not expose"}}}}
<-- {"jsonrpc":"2.0","id":6,"result":{"content":[{"type":"text","text":"where: \"internal_notes\" is not a filterable attribute (allowed: title)"}],"isError":true}}
```

Filter values must be scalars (string/number/bool/null) - `where:` builds
an ActiveRecord `.where(hash)` clause (parameterized, not string-built),
never raw SQL, so there's no injection surface; non-scalar values (e.g. a
nested object trying to smuggle an operator) are rejected before they
ever reach ActiveRecord.

## Persisting audit events with ActiveRecord

`audit_sink` accepts any callable (see Design decisions above); `acts_as_mcp`
also ships a ready-made ActiveRecord-backed one so you don't have to write
your own model + migration for the common case:

```
rails generate acts_as_mcp:audit_log
rails db:migrate
```

```ruby
ActsAsMcp.configure do |c|
  c.audit_sink = ActsAsMcp::ActiveRecordAuditSink.new
end
```

Every call - success, a `ToolError`, or an `authorize` denial - becomes one
`ActsAsMcp::AuditLog` row (`tool`, `args` as JSON, `ok`, `duration_ms`,
`error`, `occurred_at`). Same rule as everywhere else in this gem: the sink
can never take the endpoint down, so a persistence failure (table not
migrated yet, DB unreachable) is swallowed, never raised into the request.

Real output from `examples/activerecord_model.rb` (`bundle exec ruby -Ilib
examples/activerecord_model.rb`), captured 2026-08-13 - five calls from
the transcript above, including the two that returned `isError`, each
landing as a real row:

```
# every call above was persisted by ActsAsMcp::ActiveRecordAuditSink (rails generate acts_as_mcp:audit_log for the migration) - real rows, not a mock:
  #1 tool="article_list" ok=true args={"limit":10} duration_ms=4 error=nil
  #2 tool="article_get" ok=true args={"id":1} duration_ms=1 error=nil
  #3 tool="article_get" ok=false args={"id":999999} duration_ms=0 error="article 999999 not found"
  #4 tool="article_list" ok=true args={"where":{"title":"Shipping modelgate"}} duration_ms=0 error=nil
  #5 tool="article_list" ok=false args={"where":{"internal_notes":"unpublished draft, do not expose"}} duration_ms=0 error="where: \"internal_notes\" is not a filterable attribute (allowed: title)"
```

Note `#3` and `#5`: an `isError` tool result and an `authorize` denial are
both `ok=false` rows with a real `error` message - the audit trail covers
rejected calls, not just successful ones.

`ActsAsMcp::AuditLog`/`ActiveRecordAuditSink` are only defined once
ActiveRecord is already loaded (`lib/acts_as_mcp.rb` requires
`acts_as_mcp/audit_log` conditionally on `defined?(::ActiveRecord::Base)`,
the same pattern the Rails engine shim already used) - the core gem stays
zero-runtime-dependency either way.

## Demo

A real terminal recording of `examples/activerecord_model.rb` end to end:
`expose:`/`where:` registering `article_get`/`article_list` automatically,
a filtered list, a real `ToolError` for a missing id and for a
disallowed filter key, and every one of those calls landing as a real
row via `ActiveRecordAuditSink`:

```bash
asciinema play demo/acts-as-mcp-demo.cast
```

(local playback - [install asciinema](https://asciinema.org/docs/installation)
if you don't have it; no account/upload needed.)

## Benchmark: per-request dispatch overhead

`bench/throughput_bench.rb` times real `tools/call` round trips through
`Server#call` - in-process JSON-RPC dispatch overhead (parse -> route ->
authorize -> invoke -> serialize), not network/HTTP latency, which
depends on whatever Rack server you mount this behind and is outside
this gem's control to measure honestly. Real output, captured 2026-07-21,
Ruby 3.3, 5000 calls:

```
acts_as_mcp in-process tools/call dispatch: 5000 calls
  mean=0.0051ms  median=0.0040ms  p95=0.0045ms  p99=0.0245ms  min=0.0038ms  max=0.4263ms
  throughput: ~196062 calls/sec (single-threaded, in-process)
```

## Protocol surface (v0.1)

`initialize` (protocol `2025-06-18`), `notifications/initialized` (202),
`ping`, `tools/list`, `tools/call`. Stateless JSON responses; no SSE
stream, no sessions — the spec's plain-JSON response mode.

## Testing

- `test/server_core_test.rb` — full endpoint behavior with hand-registered
  tools; runs with zero gems (`ruby -Ilib -Itest test/server_core_test.rb`).
- `test/model_test.rb` — ActiveRecord integration (sqlite3 in-memory):
  exposure filtering, pagination, clamping, not-found semantics.
- `test/audit_log_test.rb` — `ActiveRecordAuditSink` against a real
  sqlite3 in-memory `acts_as_mcp_audit_logs` table: success/error/denial
  events all persisted correctly, and persistence failures never raise
  into the request.
- `test/generators/audit_log_generator_test.rb` — `rails generate
  acts_as_mcp:audit_log` via `Rails::Generators::TestCase`: the migration
  lands under `db/migrate` with a timestamp prefix, defines the expected
  columns/indexes, and (the real test, not just a content match) actually
  runs against a live sqlite3 database and creates the table.
- `examples/` and `bench/` run for real in CI too (not just committed as
  static text) - `examples/plain_tools.rb` and `bench/throughput_bench.rb`
  in the zero-gems job, `examples/activerecord_model.rb` (now also
  exercising `ActiveRecordAuditSink`) in the ActiveRecord job.

## Roadmap

- ~~`where:` filters with an allowlist~~ - shipped 0.2.0, see above.
- ~~AR-backed audit-log table + migration generator~~ - shipped 0.3.0,
  see "Persisting audit events with ActiveRecord" above.
- v0.4: opt-in write tools with per-tool policies.
- Rails engine class exists today but is a thin shim; mounting the Rack
  app is the supported path.

## License

MIT.
