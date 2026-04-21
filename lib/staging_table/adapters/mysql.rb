# frozen_string_literal: true

module StagingTable
  module Adapters
    class Mysql < Base
      def create_table(temp_table_name, source_table_name, options = {})
        # MySQL's LIKE copies structure and indexes by default
        quoted_temp = connection.quote_table_name(temp_table_name)
        quoted_source = connection.quote_table_name(source_table_name)
        connection.execute("CREATE TABLE #{quoted_temp} LIKE #{quoted_source}")

        add_extra_columns(temp_table_name, options[:extra_columns])
      end

      protected

      def sql_type_for(type)
        case type
        when :string
          "VARCHAR(255)"
        when :text
          "TEXT"
        when :integer
          "INT"
        when :bigint
          "BIGINT"
        when :float
          "DOUBLE"
        when :decimal
          "DECIMAL"
        when :boolean
          "TINYINT(1)"
        when :datetime, :timestamp
          "DATETIME"
        when :date
          "DATE"
        when :time
          "TIME"
        when :binary
          "BLOB"
        when :json
          "JSON"
        else
          raise ConfigurationError, "Unsupported column type for MySQL: #{type.inspect}"
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
    end
  end
end
