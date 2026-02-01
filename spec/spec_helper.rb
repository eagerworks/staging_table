require "bundler/setup"
require "staging_table"
require "active_record"

# Load support files
Dir[File.join(__dir__, "support", "**", "*.rb")].sort.each { |f| require f }

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.warnings = true

  config.default_formatter = "doc" if config.files_to_run.one?

  config.order = :random
  Kernel.srand config.seed

  config.before(:suite) do
    DatabaseHelper.setup_databases
  end

  config.after(:suite) do
    DatabaseHelper.teardown_databases
  end

  config.around(:each, :postgresql) do |example|
    unless DatabaseHelper.postgresql_available?
      skip "PostgreSQL not available"
    end
    DatabaseHelper.with_postgresql_connection do
      example.run
    end
  end

  config.around(:each, :mysql) do |example|
    unless DatabaseHelper.mysql_available?
      skip "MySQL not available"
    end
    DatabaseHelper.with_mysql_connection do
      example.run
    end
  end

  config.around(:each, :sqlite) do |example|
    unless DatabaseHelper.sqlite_available?
      skip "SQLite not available"
    end
    DatabaseHelper.with_sqlite_connection do
      example.run
    end
  end
end
