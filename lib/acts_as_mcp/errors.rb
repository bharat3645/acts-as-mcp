module ActsAsMcp
  class Error < StandardError; end

  # Raised by tool handlers for expected failures (e.g. record not found).
  # Surfaced to the MCP client as isError tool content, per spec — not as a
  # JSON-RPC protocol error.
  class ToolError < Error; end
end
