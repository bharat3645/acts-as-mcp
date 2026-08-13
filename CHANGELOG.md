# Changelog

## [0.3.0] - 2026-08-13

### Added
- `ActsAsMcp::ActiveRecordAuditSink` + `ActsAsMcp::AuditLog`: a ready-made
  ActiveRecord-backed `audit_sink` so every tool call (success, a
  `ToolError`, or an `authorize` denial) can be persisted without hand-
  writing a model/migration. `AuditLog`/`ActiveRecordAuditSink` are only
  defined once ActiveRecord is already loaded (`lib/acts_as_mcp.rb`
  requires `acts_as_mcp/audit_log` conditionally on
  `defined?(::ActiveRecord::Base)`, mirroring the existing Rails-engine
  shim pattern) - the core gem stays zero-runtime-dependency. The sink
  itself never raises into the request even if persistence fails (a
  missing/unmigrated table, an unreachable DB), same discipline as
  `Server#audit`'s own rescue.
- `rails generate acts_as_mcp:audit_log`: a real Rails migration
  generator (built on `ActiveRecord::Generators::Migration`, the same
  concern ActiveRecord's own generators use for `next_migration_number`/
  `db_migrate_path`) that creates the `acts_as_mcp_audit_logs` table
  migration - `tool`, `args` (JSON text), `ok`, `duration_ms`, `error`,
  `occurred_at`, indexed on `tool` and `occurred_at`.
- 5 new tests in `test/audit_log_test.rb` (success/error/denial
  persistence, multiple independent rows, and the "sink never raises"
  guarantee via a stubbed `create!` failure) + 3 in
  `test/generators/audit_log_generator_test.rb` (migration file lands
  under `db/migrate` with a timestamp prefix, defines the expected
  columns/indexes, and actually runs against a live sqlite3 database -
  not just a content-match on the generated text).
- `examples/activerecord_model.rb` extended to wire up
  `ActiveRecordAuditSink` and print the real persisted audit rows for
  every call in the transcript, including the two that returned
  `isError` - both landed as real `ok=false` rows with the actual error
  message, not silently dropped.
- README: "Persisting audit events with ActiveRecord" section with the
  real captured example output; roadmap items struck through.

### Fixed
- `acts_as_mcp.gemspec`'s `files` glob only matched `lib/**/*.rb`, which
  silently excluded the new generator's `.rb.tt` migration template (Rails'
  own convention for generator templates, so it isn't parsed as executable
  Ruby) from the packaged gem - caught by inspecting `gem spec ... files`
  on a real build before shipping, not assumed from the glob alone. Fixed
  by adding `lib/generators/**/*.tt` explicitly; verified the rebuilt gem
  actually contains the template.
- Two of the new test files (`test/audit_log_test.rb`,
  `test/generators/audit_log_generator_test.rb`) each need their own
  ActiveRecord sqlite3 `:memory:` connection. Because `rake test` loads
  every `*_test.rb` into one process, having them call
  `ActiveRecord::Base.establish_connection` like `test/model_test.rb`
  does would race it - whichever file's file-load-time `establish_connection`
  call ran last would silently wipe out the connection (and thus the
  tables) the earlier file set up, breaking that file's tests with
  a load-order-dependent "no such table" error. Caught by actually
  running `rake test` (not just each new file individually) before
  calling this done - fixed by scoping each to its own named,
  non-`ActiveRecord::Base` connection instead of the shared global one.
  Verified with 5 different `--seed` values, not just the default.

## [0.2.0] - 2026-08-12

### Added
- `acts_as_mcp expose: [...], where: [...]`: an explicit allowlist of
  attributes the generated `<model>_list` tool may be filtered on
  (exact match). First of the roadmap's three v0.2 items to ship.
  Same "nothing exposed/filterable by default" discipline as `expose:`
  itself: `where:` must be a subset of `expose:` (raises `ArgumentError`
  at registration time otherwise) - filtering on a hidden column would
  let a caller probe its value indirectly via presence/absence of
  matches, even though the value never appears in a response. Filter
  values must be scalars (string/number/bool/null); the `where` argument
  is validated before ever reaching ActiveRecord, and unknown keys or a
  non-scalar value raise a clear `ToolError` (isError content), never a
  crash or a silent no-op. Implemented via a real `.where(hash)` clause
  (parameterized, not string-built) - no new SQL-injection surface.
  `_list`'s advertised `inputSchema` gains a `where` object property
  (with `additionalProperties: false` and the allowlisted keys named)
  only when `where:` is non-empty, so tools with no filter declared are
  byte-identical to before.
- 9 new tests in `test/model_test.rb` (was 6, now 15): the subset check,
  schema shape with/without `where:` declared, a real filtered query,
  filter+pagination combined, a disallowed key, a real column rejected
  because it's not in `where:`, a non-object `where`, a non-scalar
  filter value, and the argument-omitted case still returning everything.
  `examples/activerecord_model.rb` extended with two new real, captured
  RPC round trips demonstrating an allowed filter and a rejected one.

### Documentation/example/benchmark polish (carried from Unreleased)

### Added
- `examples/plain_tools.rb`: real, runnable initialize -> tools/list ->
  tools/call sequence against hand-registered tools (zero gems needed).
- `examples/activerecord_model.rb`: same idea for the `expose:` feature,
  showing live that a non-exposed column never appears in a response
  (dev-only deps: `activerecord`, `sqlite3` - the gem itself stays
  zero-dependency).
- `bench/throughput_bench.rb`: real per-request `tools/call` dispatch
  overhead benchmark (parse -> route -> authorize -> invoke -> serialize),
  explicit that it measures in-process dispatch, not network/HTTP layer
  latency (which depends on whatever Rack server you mount this behind).
- All three run for real in CI now, not just committed as static text -
  `examples/plain_tools.rb` + `bench/throughput_bench.rb` in the
  zero-gems job, `examples/activerecord_model.rb` in the ActiveRecord job.
- README: real captured output from both examples and the benchmark,
  replacing the previous single hand-written usage snippet.

## [0.1.0] - 2026-07-17

Initial release.

- `ActsAsMcp::Server`: zero-dependency Rack-compatible MCP endpoint
  (Streamable HTTP, stateless JSON): `initialize`, `notifications/initialized`,
  `ping`, `tools/list`, `tools/call`; JSON-RPC error semantics (-32700/-32601/-32602);
  expected tool failures as `isError` content; unexpected exceptions never
  leak details to the client.
- `ActsAsMcp::Model#acts_as_mcp expose: [...]`: read-only `_get`/`_list`
  tools per model with required explicit attribute exposure and clamped
  pagination.
- `ActsAsMcp.configure`: `authorize` hook (per call: env, tool, args) and
  `audit_sink` (tool, args, outcome, duration; sink failures can never
  break the request).
- Optional `Rails::Engine` shim; mounting the Rack app is the supported path.
