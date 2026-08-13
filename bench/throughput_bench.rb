# frozen_string_literal: true

# Real per-request dispatch overhead benchmark: N real tools/call
# round trips through the real Server#call, timed with
# Process.clock_gettime. Measures in-process JSON-RPC dispatch overhead
# (parse -> route -> authorize -> invoke -> serialize) - NOT network/HTTP
# layer latency, which depends entirely on whatever Rack server you
# mount this behind (Puma, Unicorn, WEBrick, ...) and is outside this
# gem's control to measure honestly.
#
#   ruby -Ilib bench/throughput_bench.rb [N]   # N defaults to 5000

require "acts_as_mcp"
require "json"
require "stringio"

N = (ARGV[0] || 5000).to_i

ActsAsMcp.registry.register(ActsAsMcp::Tool.new(
  name: "echo",
  description: "echo back",
  input_schema: {"type" => "object"},
  handler: ->(args) { {"echo" => args} }
))

server = ActsAsMcp::Server.new
payload = JSON.generate({jsonrpc: "2.0", id: 1, method: "tools/call",
                           params: {name: "echo", arguments: {text: "bench"}}})

def call_once(server, payload)
  env = {"REQUEST_METHOD" => "POST", "rack.input" => StringIO.new(payload)}
  server.call(env)
end

# Warm up (JIT/GC settle) before timing - the first few calls in any Ruby
# process include one-time costs (method caches, GC pauses from earlier
# setup) that would skew a small N.
50.times { call_once(server, payload) }

samples = Array.new(N) do
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  call_once(server, payload)
  (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000.0 # ms
end.sort

mean = samples.sum / samples.size
median = samples[samples.size / 2]
p95 = samples[(samples.size * 0.95).to_i]
p99 = samples[(samples.size * 0.99).to_i]

puts "acts_as_mcp in-process tools/call dispatch: #{N} calls"
puts format("  mean=%.4fms  median=%.4fms  p95=%.4fms  p99=%.4fms  min=%.4fms  max=%.4fms",
  mean, median, p95, p99, samples.first, samples.last)
puts format("  throughput: ~%.0f calls/sec (single-threaded, in-process)", 1000.0 / mean)
