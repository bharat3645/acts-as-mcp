require "active_record"
require_relative "../test_helper"
require "rails/generators/test_case"
require_relative "../../lib/generators/acts_as_mcp/audit_log/audit_log_generator"

# A real, isolated AR connection for actually running the generated
# migration against - `establish_connection` rejects anonymous classes,
# and reusing ActiveRecord::Base directly would collide with the other
# *_test.rb files sharing this process under `rake test` (see the note
# in the test below).
class AuditLogGeneratorTestConnection < ActiveRecord::Base
  self.abstract_class = true
end

class AuditLogGeneratorTest < Rails::Generators::TestCase
  tests ActsAsMcp::Generators::AuditLogGenerator
  destination File.expand_path("../../tmp/generator_dest", __dir__)
  setup :prepare_destination

  def test_generates_a_timestamped_migration_under_db_migrate
    run_generator
    migration = migration_file("db/migrate/create_acts_as_mcp_audit_logs.rb")
    assert migration, "expected a db/migrate/*_create_acts_as_mcp_audit_logs.rb file"
  end

  def test_migration_defines_the_expected_table
    run_generator
    content = File.read(migration_file("db/migrate/create_acts_as_mcp_audit_logs.rb"))

    assert_match(/class CreateActsAsMcpAuditLogs < ActiveRecord::Migration\[[\d.]+\]/, content)
    assert_match(/create_table :acts_as_mcp_audit_logs/, content)
    %w[tool args ok duration_ms error occurred_at].each do |column|
      assert_match(/:#{column}/, content)
    end
    assert_match(/t\.string :tool, null: false/, content)
    assert_match(/t\.boolean :ok, null: false/, content)
    assert_match(/t\.datetime :occurred_at, null: false/, content)
    assert_match(/add_index :acts_as_mcp_audit_logs, :tool/, content)
    assert_match(/add_index :acts_as_mcp_audit_logs, :occurred_at/, content)
  end

  def test_generated_migration_actually_runs_against_a_real_database
    run_generator
    migration_path = migration_file("db/migrate/create_acts_as_mcp_audit_logs.rb")

    # A dedicated, named connection (not ActiveRecord::Base's shared one) -
    # `rake test` runs every *_test.rb in one process, and re-establishing
    # ActiveRecord::Base's global :memory: connection here would silently
    # wipe out whatever tables model_test.rb/audit_log_test.rb already
    # created on it, depending on file-load order. See audit_log_test.rb
    # for the same discipline applied to ActsAsMcp::AuditLog itself.
    scoped_connection = AuditLogGeneratorTestConnection
    scoped_connection.establish_connection(adapter: "sqlite3", database: ":memory:")
    load migration_path
    migration = CreateActsAsMcpAuditLogs.new
    migration.define_singleton_method(:connection) { scoped_connection.connection }
    migration.change

    assert scoped_connection.connection.table_exists?(:acts_as_mcp_audit_logs)
    columns = scoped_connection.connection.columns(:acts_as_mcp_audit_logs).map(&:name)
    assert_includes columns, "tool"
    assert_includes columns, "occurred_at"
  end

  private

  def migration_file(relative_path)
    dir, base = File.split(relative_path)
    Dir.glob(File.join(destination_root, dir, "[0-9]*_#{File.basename(base)}")).first
  end
end
