require "json"
require "time"

module ActsAsMcp
  # Optional ActiveRecord-backed audit_sink. Not required by the core gem
  # (keeps it zero-runtime-dependency) - only loaded when the host app has
  # already loaded ActiveRecord, mirroring engine.rb's Rails-optional
  # pattern (`require_relative "acts_as_mcp/audit_log" if
  # defined?(::ActiveRecord::Base)` in acts_as_mcp.rb).
  #
  #   rails generate acts_as_mcp:audit_log
  #   rails db:migrate
  #
  #   ActsAsMcp.configure do |c|
  #     c.audit_sink = ActsAsMcp::ActiveRecordAuditSink.new
  #   end
  class AuditLog < ActiveRecord::Base
    self.table_name = "acts_as_mcp_audit_logs"
  end

  # Callable audit_sink: persists every tool-call event (tool, args,
  # outcome, duration, error) emitted by Server#audit to the
  # acts_as_mcp_audit_logs table. Server#audit already rescues any sink
  # error so it never reaches the request, but #call also guards its own
  # write (e.g. the table not migrated yet) for the same reason - an
  # audit sink must never be able to take the endpoint down.
  class ActiveRecordAuditSink
    def call(event)
      AuditLog.create!(
        tool: event[:tool].to_s,
        args: JSON.generate(event[:args]),
        ok: !!event[:ok],
        duration_ms: event[:duration_ms],
        error: event[:error],
        occurred_at: event[:at] ? Time.parse(event[:at].to_s) : Time.now.utc
      )
    rescue StandardError
      nil
    end
  end
end
