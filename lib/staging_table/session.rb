# frozen_string_literal: true

require "securerandom"

module StagingTable
  class Session
    attr_reader :source_model, :staging_model, :options

    # Supported callback options:
    #   - before_insert: ->(session) { ... }
    #   - after_insert: ->(session, records) { ... }
    #   - before_transfer: ->(session) { ... }
    #   - after_transfer: ->(session, result) { ... }
    CALLBACK_OPTIONS = %i[before_insert after_insert before_transfer after_transfer].freeze

    def initialize(source_model, **options)
      @source_model = source_model
      config = StagingTable.configuration
      @callbacks = options.slice(*CALLBACK_OPTIONS)
      @options = {
        batch_size: config.default_batch_size,
        transfer_strategy: config.default_transfer_strategy
      }.merge(options.except(*CALLBACK_OPTIONS))
      @table_created = false
    end

    def create_table
      return if @table_created

      payload = {
        source_model: source_model,
        source_table: source_model.table_name,
        staging_table: staging_table_name
      }

      Instrumentation.instrument(:create_table, payload) do
        adapter.create_table(staging_table_name, source_model.table_name, options)
        @staging_model = ModelFactory.build(source_model, staging_table_name, excluded_columns: options[:excluded_columns] || [])
        @table_created = true
      end
    end

    def drop_table
      return unless @table_created

      payload = {
        source_model: source_model,
        source_table: source_model.table_name,
        staging_table: staging_table_name
      }

      Instrumentation.instrument(:drop_table, payload) do
        adapter.drop_table(staging_table_name)
        @table_created = false
        @staging_model = nil
      end
    end

    def insert(records)
      ensure_table_created!

      run_callback(:before_insert, self)

      normalized_records = normalize_records(records)

      payload = {
        source_model: source_model,
        source_table: source_model.table_name,
        staging_table: staging_table_name,
        record_count: normalized_records.size,
        batch_size: options[:batch_size] || 1000
      }

      Instrumentation.instrument(:insert, payload) do
        BulkInserter.new(staging_model, batch_size: options[:batch_size] || 1000).insert(normalized_records)
      end

      run_callback(:after_insert, self, normalized_records)
    end

    def insert_from_query(relation)
      ensure_table_created!

      run_callback(:before_insert, self)

      # TODO: Implement direct INSERT INTO SELECT for query-based insertion
      # For now, we'll iterate, but this should be optimized
      all_records = []

      payload = {
        source_model: source_model,
        source_table: source_model.table_name,
        staging_table: staging_table_name,
        batch_size: options[:batch_size] || 1000
      }

      Instrumentation.instrument(:insert, payload) do |instrumentation_payload|
        relation.find_in_batches(batch_size: options[:batch_size] || 1000) do |batch|
          records = batch.map(&:attributes)
          all_records.concat(records)
          BulkInserter.new(staging_model, batch_size: options[:batch_size] || 1000).insert(records)
        end
        instrumentation_payload[:record_count] = all_records.size
      end

      run_callback(:after_insert, self, all_records)
    end

    def transfer
      ensure_table_created!

      run_callback(:before_transfer, self)

      strategy_name = options[:transfer_strategy].to_s.camelize
      begin
        strategy_class = TransferStrategies.const_get(strategy_name)
      rescue NameError
        raise ConfigurationError, "Invalid transfer strategy: #{options[:transfer_strategy]}. Available strategies: insert, upsert."
      end

      payload = {
        source_model: source_model,
        source_table: source_model.table_name,
        staging_table: staging_table_name,
        strategy: options[:transfer_strategy],
        staged_count: staging_model.count
      }

      result = Instrumentation.instrument(:transfer, payload) do |instrumentation_payload|
        transfer_result = strategy_class.new(source_model, staging_model, options).transfer
        instrumentation_payload[:result] = transfer_result
        transfer_result
      end

      run_callback(:after_transfer, self, result)

      result
    end

    # Delegate unknown methods to the staging model (e.g. for querying)
    def method_missing(method, *args, &block)
      if staging_model.respond_to?(method)
        staging_model.send(method, *args, &block)
      else
        super
      end
    end

    def respond_to_missing?(method, include_private = false)
      staging_model.respond_to?(method, include_private) || super
    end

    private

    def run_callback(name, *args)
      callback = @callbacks[name]
      return unless callback

      callback.call(*args)
    end

    def adapter
      @adapter ||= Adapters::Base.for(source_model.connection)
    end

    def staging_table_name
      @staging_table_name ||= "staging_#{source_model.table_name}_#{SecureRandom.hex(8)}"
    end

    def ensure_table_created!
      raise TableError, "Staging table has not been created. You must call #create_table or use StagingTable.stage with a block before inserting or transferring data." unless @table_created
    end

    def normalize_records(records)
      return records unless records.is_a?(ActiveRecord::Relation) || records.is_a?(Array)

      records.map { |record| normalize_record(record) }
    end

    def normalize_record(record)
      return record unless record.is_a?(ActiveRecord::Base)

      record.attributes_for_database
    end
  end
end
