# Changelog

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
