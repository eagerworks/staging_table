# frozen_string_literal: true

module StagingTable
  module Adapters
    class Postgresql < Base
      def create_table(temp_table_name, source_table_name, options = {})
        quoted_temp = connection.quote_table_name(temp_table_name)
        quoted_source = connection.quote_table_name(source_table_name)
        sql = "CREATE TABLE #{quoted_temp} (LIKE #{quoted_source} INCLUDING DEFAULTS"
        sql += " INCLUDING INDEXES" if options[:include_indexes]
        sql += ")"
        connection.execute(sql)

        add_extra_columns(temp_table_name, options[:extra_columns])
      end

      protected

      def sql_type_for(type)
        case type
        when :string
          "VARCHAR"
        when :text
          "TEXT"
        when :integer
          "INTEGER"
        when :bigint
          "BIGINT"
        when :float
          "DOUBLE PRECISION"
        when :decimal
          "DECIMAL"
        when :boolean
          "BOOLEAN"
        when :datetime, :timestamp
          "TIMESTAMP"
        when :date
          "DATE"
        when :time
          "TIME"
        when :binary
          "BYTEA"
        when :json
          "JSON"
        when :jsonb
          "JSONB"
        when :uuid
          "UUID"
        else
          raise ConfigurationError, "Unsupported column type for PostgreSQL: #{type.inspect}"
        end
      end

      def quote_default(value)
        case value
        when true
          "true"
        when false
          "false"
        else
          super
        end
      end
    end
  end
end
