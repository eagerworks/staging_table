# frozen_string_literal: true

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
        staged_count = @staging_model.count
        return TransferResult.new if staged_count.zero?

        # Only transfer columns that exist on both staging and source tables
        transferable_columns = @staging_model.column_names & @source_model.column_names
        columns = transferable_columns.map { |c| @connection.quote_column_name(c) }.join(", ")
        source_table = @connection.quote_table_name(@source_model.table_name)
        staging_table = @connection.quote_table_name(@staging_model.table_name)

        sql = <<~SQL
          INSERT INTO #{source_table} (#{columns})
          SELECT #{columns} FROM #{staging_table}
        SQL

        @connection.execute(sql)

        # For plain INSERT, all staged records are inserted (assuming no constraint violations)
        TransferResult.new(inserted: staged_count)
      end
    end
  end
end
