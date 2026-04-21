# frozen_string_literal: true

module StagingTable
  module Adapters
    class Base
      attr_reader :connection

      def initialize(connection)
        @connection = connection
      end

      def create_table(temp_table_name, source_table_name, options = {})
        raise NotImplementedError
      end

      def drop_table(temp_table_name)
        quoted_table = connection.quote_table_name(temp_table_name)
        connection.execute("DROP TABLE IF EXISTS #{quoted_table}")
      end

      def self.for(connection)
        adapter_name = connection.adapter_name.downcase
        case adapter_name
        when /postgresql/
          Postgresql.new(connection)
        when /mysql|trilogy/
          Mysql.new(connection)
        when /sqlite/
          Sqlite.new(connection)
        else
          raise AdapterError, "Unsupported adapter: #{adapter_name}. StagingTable supports PostgreSQL, MySQL, and SQLite adapters."
        end
      end

      protected

      def add_extra_columns(table_name, extra_columns)
        return if extra_columns.nil? || extra_columns.empty?

        extra_columns.each do |column_name, column_spec|
          add_column(table_name, column_name, column_spec)
        end
      end

      def add_column(table_name, column_name, column_spec)
        quoted_table = connection.quote_table_name(table_name)
        quoted_column = connection.quote_column_name(column_name)
        column_definition = parse_column_spec(column_spec)

        sql = "ALTER TABLE #{quoted_table} ADD COLUMN #{quoted_column} #{column_definition}"
        connection.execute(sql)
      end

      def parse_column_spec(spec)
        if spec.is_a?(Symbol)
          sql_type_for(spec)
        elsif spec.is_a?(Hash)
          type = sql_type_for(spec[:type])
          parts = [type]
          parts << "DEFAULT #{quote_default(spec[:default])}" if spec.key?(:default)
          parts << "NOT NULL" if spec[:null] == false
          parts.join(" ")
        else
          raise ConfigurationError, "Invalid column spec: #{spec.inspect}. Must be a symbol or hash with :type key."
        end
      end

      def sql_type_for(type)
        case type
        when :string, :text
          "TEXT"
        when :integer
          "INTEGER"
        when :float
          "REAL"
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
          "BLOB"
        when :json, :jsonb
          "TEXT"
        else
          raise ConfigurationError, "Unsupported column type: #{type.inspect}"
        end
      end

      def quote_default(value)
        case value
        when nil
          "NULL"
        when true
          "TRUE"
        when false
          "FALSE"
        when Numeric
          value.to_s
        when String
          connection.quote(value)
        else
          connection.quote(value.to_s)
        end
      end
    end
  end
end
