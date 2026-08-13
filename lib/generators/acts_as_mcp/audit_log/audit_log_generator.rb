require "rails/generators"
require "rails/generators/active_record"

module ActsAsMcp
  module Generators
    # rails generate acts_as_mcp:audit_log
    #
    # Creates the migration for ActsAsMcp::ActiveRecordAuditSink's backing
    # table (acts_as_mcp_audit_logs). Built on ActiveRecord's own
    # Rails::Generators::Migration concern (next_migration_number,
    # db_migrate_path) rather than hand-rolling either, so this plays
    # nicely with a configured custom migrations path / multiple
    # databases the same way any of Rails' own migration generators do.
    class AuditLogGenerator < ::Rails::Generators::Base
      include ::ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      def create_migration_file
        migration_template "create_acts_as_mcp_audit_logs.rb.tt",
                            File.join(db_migrate_path, "create_acts_as_mcp_audit_logs.rb")
      end
    end
  end
end
