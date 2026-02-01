module StagingTable
  module TransferStrategies
    class Upsert
      def initialize(source_model, staging_model, options = {})
        @source_model = source_model
        @staging_model = staging_model
        @options = options
        @connection = source_model.connection
      end

      def transfer
        adapter_name = @connection.adapter_name.downcase
        case adapter_name
        when /postgresql/
          postgresql_upsert
        when /mysql/
          mysql_upsert
        else
          raise AdapterError, "Upsert strategy not supported for adapter: #{adapter_name}. Supported adapters are PostgreSQL and MySQL."
        end
      end

      private

      def postgresql_upsert
        conflict_target = Array(@options[:conflict_target])
        if conflict_target.empty?
          raise ConfigurationError, "PostgreSQL upsert requires :conflict_target option specifying the unique constraint columns. Example: transfer_strategy: :upsert, conflict_target: [:email]"
        end

        columns = column_names.map { |c| quote_column(c) }.join(", ")
        conflict_target_sql = conflict_target.map { |c| quote_column(c) }.join(", ")
        source_table = quote_table(@source_model.table_name)
        staging_table = quote_table(@staging_model.table_name)

        sql = "INSERT INTO #{source_table} (#{columns}) SELECT #{columns} FROM #{staging_table}"
        sql += " ON CONFLICT (#{conflict_target_sql})"

        if @options[:conflict_action] == :ignore
          sql += " DO NOTHING"
        else
          updates = column_names.reject { |c| conflict_target.map(&:to_s).include?(c.to_s) || c == "id" }
            .map { |c| "#{quote_column(c)} = EXCLUDED.#{quote_column(c)}" }.join(", ")
          sql += " DO UPDATE SET #{updates}"
        end

        @connection.execute(sql)
      end

      def mysql_upsert
        columns = column_names.map { |c| quote_column(c) }.join(", ")
        source_table = quote_table(@source_model.table_name)
        staging_table = quote_table(@staging_model.table_name)

        if @options[:conflict_action] == :ignore
          sql = "INSERT IGNORE INTO #{source_table} (#{columns}) SELECT #{columns} FROM #{staging_table}"
        else
          sql = "INSERT INTO #{source_table} (#{columns}) SELECT #{columns} FROM #{staging_table}"
          updates = column_names.reject { |c| c == "id" }
            .map { |c| "#{quote_column(c)} = VALUES(#{quote_column(c)})" }.join(", ")
          sql += " ON DUPLICATE KEY UPDATE #{updates}"
        end

        @connection.execute(sql)
      end

      def column_names
        @staging_model.column_names
      end

      def quote_column(name)
        @connection.quote_column_name(name)
      end

      def quote_table(name)
        @connection.quote_table_name(name)
      end
    end
  end
end
