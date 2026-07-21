# Changelog

## [Unreleased]

Documentation/example/benchmark polish - no library code changes.

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
