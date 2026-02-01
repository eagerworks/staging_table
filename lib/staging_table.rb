require "active_record"
require "staging_table/version"
require "staging_table/errors"
require "staging_table/configuration"
require "staging_table/instrumentation"
require "staging_table/transfer_result"
require "staging_table/session"
require "staging_table/model_factory"
require "staging_table/bulk_inserter"
require "staging_table/adapters/base"
require "staging_table/adapters/postgresql"
require "staging_table/adapters/mysql"
require "staging_table/adapters/sqlite"
require "staging_table/transfer_strategies/insert"
require "staging_table/transfer_strategies/upsert"

module StagingTable
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    # Stage data for bulk import into a model's table.
    #
    # @param source_model [Class] The ActiveRecord model to stage data for
    # @param options [Hash] Configuration options
    # @option options [Integer] :batch_size Number of records per batch (default: 1000)
    # @option options [Symbol] :transfer_strategy :insert or :upsert (default: :insert)
    # @option options [Array<Symbol>] :conflict_target Columns for upsert conflict detection
    # @option options [Symbol] :conflict_action :update or :ignore for upsert conflicts
    # @option options [Proc] :before_insert Called before inserting into staging
    # @option options [Proc] :after_insert Called after inserting into staging
    # @option options [Proc] :before_transfer Called before transferring to target
    # @option options [Proc] :after_transfer Called after transferring to target
    #
    # @yield [session] Block for staging operations
    # @yieldparam session [Session] The staging session
    # @return [TransferResult, Session] TransferResult when block given, Session otherwise
    def stage(source_model, **options, &block)
      session = Session.new(source_model, **options)

      if block
        payload = {
          source_model: source_model,
          source_table: source_model.table_name,
          options: options.except(*Session::CALLBACK_OPTIONS)
        }

        Instrumentation.instrument(:stage, payload) do |instrumentation_payload|
          begin
            session.create_table
            yield(session)
            result = session.transfer
            instrumentation_payload[:result] = result
            result
          ensure
            session.drop_table
          end
        end
      else
        session.create_table
        session
      end
    end
  end
end
