# frozen_string_literal: true

module StagingTable
  module Adapters
    class Sqlite < Base
      def create_table(temp_table_name, source_table_name, options = {})
        quoted_temp = connection.quote_table_name(temp_table_name)
        connection.quote_table_name(source_table_name)

        # SQLite doesn't support CREATE TABLE ... LIKE, so we copy the structure
        # by getting the original CREATE TABLE statement and modifying it
        create_sql = connection.select_value(
          "SELECT sql FROM sqlite_master WHERE type='table' AND name=#{connection.quote(source_table_name)}"
        )

        if create_sql.nil?
          raise TableError, "Source table '#{source_table_name}' does not exist"
        end

        # Replace the table name in the CREATE TABLE statement
        new_create_sql = create_sql.sub(/CREATE\s+TABLE\s+["'`]?#{Regexp.escape(source_table_name)}["'`]?/i, "CREATE TABLE #{quoted_temp}")

        connection.execute(new_create_sql)

        # Copy indexes if requested
        if options[:include_indexes]
          copy_indexes(temp_table_name, source_table_name)
        end

        add_extra_columns(temp_table_name, options[:extra_columns])
      end

      protected

      def sql_type_for(type)
        case type
        when :string, :text
          "TEXT"
        when :integer, :bigint
          "INTEGER"
        when :float, :decimal
          "REAL"
        when :boolean
          "INTEGER"
        when :datetime, :timestamp, :date, :time
          "TEXT"
        when :binary
          "BLOB"
        when :json, :jsonb
          "TEXT"
        else
          raise ConfigurationError, "Unsupported column type for SQLite: #{type.inspect}"
        end
      end

      def quote_default(value)
        case value
        when true
          "1"
        when false
          "0"
        else
          super
        end
      end

      private

      def copy_indexes(temp_table_name, source_table_name)
        indexes = connection.select_all(
          "SELECT sql FROM sqlite_master WHERE type='index' AND tbl_name=#{connection.quote(source_table_name)} AND sql IS NOT NULL"
        )

        indexes.each do |row|
          index_sql = row["sql"]
          next if index_sql.nil?

          # Replace the table name and generate a new index name
          new_index_sql = index_sql.gsub(/\b#{Regexp.escape(source_table_name)}\b/, temp_table_name)
          # Make index name unique by appending temp table name suffix
          new_index_sql = new_index_sql.sub(/INDEX\s+["'`]?(\w+)["'`]?/i) do
            "INDEX #{$1}_#{temp_table_name.split("_").last}"
          end

          connection.execute(new_index_sql)
        end
      end
    end
  end
end
