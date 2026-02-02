# frozen_string_literal: true

require "fileutils"

module DatabaseHelper
  class << self
    def setup_databases
      setup_postgresql if postgresql_available?
      setup_mysql if mysql_available?
      setup_sqlite if sqlite_available?
    end

    def teardown_databases
      teardown_postgresql if postgresql_available?
      teardown_mysql if mysql_available?
      teardown_sqlite if sqlite_available?
    end

    def postgresql_available?
      return @postgresql_available if defined?(@postgresql_available)

      @postgresql_available = begin
        require "pg"
        ActiveRecord::Base.establish_connection(postgresql_config)
        ActiveRecord::Base.connection.execute("SELECT 1")
        true
      rescue LoadError, ActiveRecord::ConnectionNotEstablished, ActiveRecord::NoDatabaseError, PG::Error => e
        warn "PostgreSQL not available: #{e.message}"
        false
      ensure
        begin
          ActiveRecord::Base.connection_pool.disconnect!
        rescue
          nil
        end
      end
    end

    def mysql_available?
      return @mysql_available if defined?(@mysql_available)

      @mysql_available = begin
        require "mysql2"
        ActiveRecord::Base.establish_connection(mysql_config)
        ActiveRecord::Base.connection.execute("SELECT 1")
        true
      rescue LoadError, ActiveRecord::ConnectionNotEstablished, ActiveRecord::NoDatabaseError, Mysql2::Error => e
        warn "MySQL not available: #{e.message}"
        false
      ensure
        begin
          ActiveRecord::Base.connection_pool.disconnect!
        rescue
          nil
        end
      end
    end

    def sqlite_available?
      return @sqlite_available if defined?(@sqlite_available)

      @sqlite_available = begin
        require "sqlite3"
        ActiveRecord::Base.establish_connection(sqlite_config)
        ActiveRecord::Base.connection.execute("SELECT 1")
        true
      rescue LoadError, ActiveRecord::ConnectionNotEstablished => e
        warn "SQLite not available: #{e.message}"
        false
      ensure
        begin
          ActiveRecord::Base.connection_pool.disconnect!
        rescue
          nil
        end
      end
    end

    def with_postgresql_connection(&block)
      return false unless postgresql_available?
      reset_model_connections
      ActiveRecord::Base.establish_connection(postgresql_config)
      block.call
      true
    ensure
      ActiveRecord::Base.connection_pool.disconnect!
    end

    def with_mysql_connection(&block)
      return false unless mysql_available?
      reset_model_connections
      ActiveRecord::Base.establish_connection(mysql_config)
      block.call
      true
    ensure
      ActiveRecord::Base.connection_pool.disconnect!
    end

    def with_sqlite_connection(&block)
      return false unless sqlite_available?
      reset_model_connections
      ActiveRecord::Base.establish_connection(sqlite_config)
      block.call
      true
    ensure
      ActiveRecord::Base.connection_pool.disconnect!
    end

    def reset_model_connections
      # Clear statement caches and reset model connections when switching adapters
      # This prevents prepared statement format mismatches across different adapters
      TestUser.reset_column_information if defined?(TestUser)
      ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:clear_cache!)
    end

    def postgresql_config
      {
        adapter: "postgresql",
        database: ENV.fetch("POSTGRES_DB", "staging_table_test"),
        username: ENV.fetch("POSTGRES_USER", ENV["USER"]),
        password: ENV.fetch("POSTGRES_PASSWORD", ""),
        host: ENV.fetch("POSTGRES_HOST", "localhost"),
        port: ENV.fetch("POSTGRES_PORT", 5432)
      }
    end

    def mysql_config
      {
        adapter: "mysql2",
        database: ENV.fetch("MYSQL_DB", "staging_table_test"),
        username: ENV.fetch("MYSQL_USER", "root"),
        password: ENV.fetch("MYSQL_PASSWORD", ""),
        host: ENV.fetch("MYSQL_HOST", "127.0.0.1"),
        port: ENV.fetch("MYSQL_PORT", 3306)
      }
    end

    def sqlite_config
      {
        adapter: "sqlite3",
        database: ENV.fetch("SQLITE_DB", "tmp/staging_table_test.sqlite3")
      }
    end

    private

    def setup_postgresql
      ActiveRecord::Base.establish_connection(postgresql_config)
      create_test_tables
    end

    def setup_mysql
      ActiveRecord::Base.establish_connection(mysql_config)
      create_test_tables
    end

    def teardown_postgresql
      ActiveRecord::Base.establish_connection(postgresql_config)
      drop_test_tables
    rescue
      nil
    end

    def teardown_mysql
      ActiveRecord::Base.establish_connection(mysql_config)
      drop_test_tables
    rescue
      nil
    end

    def setup_sqlite
      FileUtils.mkdir_p("tmp")
      ActiveRecord::Base.establish_connection(sqlite_config)
      create_sqlite_test_tables
    end

    def teardown_sqlite
      ActiveRecord::Base.establish_connection(sqlite_config)
      drop_test_tables
      FileUtils.rm_f(sqlite_config[:database])
    rescue
      nil
    end

    def create_test_tables
      ActiveRecord::Base.connection.execute(<<~SQL)
        DROP TABLE IF EXISTS test_users
      SQL

      ActiveRecord::Base.connection.execute(<<~SQL)
        CREATE TABLE test_users (
          id SERIAL PRIMARY KEY,
          name VARCHAR(255),
          email VARCHAR(255),
          age INTEGER,
          active BOOLEAN DEFAULT true,
          created_at TIMESTAMP,
          updated_at TIMESTAMP
        )
      SQL

      # Add unique index for upsert tests
      ActiveRecord::Base.connection.execute(<<~SQL)
        CREATE UNIQUE INDEX test_users_email_idx ON test_users (email)
      SQL
    rescue => e
      warn "Failed to create test tables: #{e.message}"
    end

    def create_sqlite_test_tables
      ActiveRecord::Base.connection.execute(<<~SQL)
        DROP TABLE IF EXISTS test_users
      SQL

      ActiveRecord::Base.connection.execute(<<~SQL)
        CREATE TABLE test_users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name VARCHAR(255),
          email VARCHAR(255),
          age INTEGER,
          active BOOLEAN DEFAULT 1,
          created_at DATETIME,
          updated_at DATETIME
        )
      SQL

      # Add unique index for upsert tests
      ActiveRecord::Base.connection.execute(<<~SQL)
        CREATE UNIQUE INDEX test_users_email_idx ON test_users (email)
      SQL
    rescue => e
      warn "Failed to create SQLite test tables: #{e.message}"
    end

    def drop_test_tables
      ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS test_users")
      # Clean up any staging tables that might have been left behind
      staging_tables = ActiveRecord::Base.connection.tables.select { |t| t.start_with?("staging_") }
      staging_tables.each do |table|
        ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS #{table}")
      end
    rescue
      nil
    end
  end
end
