module StagingTable
  module TransferStrategies
    class Insert
      def initialize(source_model, staging_model, options = {})
        @source_model = source_model
        @staging_model = staging_model
        @options = options
        @connection = source_model.connection
      end

      def transfer
        columns = @staging_model.column_names.map { |c| @connection.quote_column_name(c) }.join(", ")
        source_table = @connection.quote_table_name(@source_model.table_name)
        staging_table = @connection.quote_table_name(@staging_model.table_name)

        sql = <<~SQL
          INSERT INTO #{source_table} (#{columns})
          SELECT #{columns} FROM #{staging_table}
        SQL

        @connection.execute(sql)
      end
    end
  end
end
