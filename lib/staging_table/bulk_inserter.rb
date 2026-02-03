# frozen_string_literal: true

module StagingTable
  class BulkInserter
    attr_reader :model, :batch_size

    def initialize(model, batch_size: 1000)
      @model = model
      @batch_size = batch_size
    end

    def insert(records)
      return if records.empty?

      unless records.all? { |r| r.is_a?(Hash) }
        raise RecordError, "All records must be hashes. If passing ActiveRecord objects, use Session#insert which normalizes them automatically."
      end

      columns = records.first.keys.map(&:to_s)
      quoted_columns = columns.map { |c| connection.quote_column_name(c) }.join(", ")
      quoted_table = connection.quote_table_name(model.table_name)

      records.each_slice(batch_size) do |batch|
        values_list = batch.map do |record|
          "(" + columns.map { |col| quote(record.key?(col.to_sym) ? record[col.to_sym] : record[col]) }.join(", ") + ")"
        end.join(", ")

        sql = "INSERT INTO #{quoted_table} (#{quoted_columns}) VALUES #{values_list}"
        connection.execute(sql)
      end
    end

    private

    def connection
      model.connection
    end

    def quote(value)
      case value
      when Array, Hash
        connection.quote(value.to_json)
      else
        connection.quote(value)
      end
    end
  end
end
