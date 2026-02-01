require "securerandom"

module StagingTable
  class Session
    attr_reader :source_model, :staging_model, :options

    def initialize(source_model, **options)
      @source_model = source_model
      config = StagingTable.configuration
      @options = {
        batch_size: config.default_batch_size,
        transfer_strategy: config.default_transfer_strategy
      }.merge(options)
      @table_created = false
    end

    def create_table
      return if @table_created

      adapter.create_table(staging_table_name, source_model.table_name, options)
      @staging_model = ModelFactory.build(source_model, staging_table_name, excluded_columns: options[:excluded_columns] || [])
      @table_created = true
    end

    def drop_table
      return unless @table_created

      adapter.drop_table(staging_table_name)
      @table_created = false
      @staging_model = nil
    end

    def insert(records)
      ensure_table_created!
      normalized_records = normalize_records(records)
      BulkInserter.new(staging_model, batch_size: options[:batch_size] || 1000).insert(normalized_records)
    end

    def insert_from_query(relation)
      ensure_table_created!
      # TODO: Implement direct INSERT INTO SELECT for query-based insertion
      # For now, we'll iterate, but this should be optimized
      relation.find_in_batches(batch_size: options[:batch_size] || 1000) do |batch|
        insert(batch.map(&:attributes))
      end
    end

    def transfer
      ensure_table_created!
      strategy_name = options[:transfer_strategy].to_s.camelize
      begin
        strategy_class = TransferStrategies.const_get(strategy_name)
      rescue NameError
        raise ConfigurationError, "Invalid transfer strategy: #{options[:transfer_strategy]}. Available strategies: insert, upsert."
      end
      strategy_class.new(source_model, staging_model, options).transfer
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
      if records.is_a?(ActiveRecord::Relation)
        records.map(&:attributes)
      elsif records.respond_to?(:to_a)
        records.to_a.map do |record|
          record.is_a?(ActiveRecord::Base) ? record.attributes : record
        end
      else
        records
      end
    end
  end
end
