# frozen_string_literal: true

require "json"

module StagingTable
  class BulkInserter
    attr_reader :model, :batch_size, :conflict_resolver

    def initialize(model, batch_size: 1000, insert_on_conflict: nil)
      @model = model
      @batch_size = batch_size
      @conflict_resolver = ConflictResolver.new(connection, insert_on_conflict)
    end

    def insert(records)
      return if records.empty?

      unless records.all? { |r| r.is_a?(Hash) }
        raise RecordError, "All records must be hashes. If passing ActiveRecord objects, use Session#insert which normalizes them automatically."
      end

      records = apply_timestamps(records)

      columns = records.first.keys.map(&:to_s)
      quoted_columns = columns.map { |c| connection.quote_column_name(c) }.join(", ")
      quoted_table = connection.quote_table_name(model.table_name)

      records.each_slice(batch_size) do |batch|
        values_list = batch.map do |record|
          "(" + columns.map { |col| quote(record.key?(col.to_sym) ? record[col.to_sym] : record[col]) }.join(", ") + ")"
        end.join(", ")

        sql = "INSERT INTO #{quoted_table} (#{quoted_columns}) VALUES #{values_list}"
        sql += conflict_resolver.conflict_clause(model.table_name)
        connection.execute(sql)
      end
    end

    private

    TIMESTAMP_COLUMNS = %w[created_at updated_at].freeze

    def apply_timestamps(records)
      return records if records.empty?

      sample_record = records.first
      model_columns = model.column_names

      missing_timestamps = TIMESTAMP_COLUMNS.select do |col|
        model_columns.include?(col) && !record_has_key?(sample_record, col)
      end

      return records if missing_timestamps.empty?

      now = Time.current
      records.map do |record|
        record = record.dup
        missing_timestamps.each { |col| record[col.to_sym] = now }
        record
      end
    end

    def record_has_key?(record, key)
      record.key?(key.to_sym) || record.key?(key.to_s)
    end

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
