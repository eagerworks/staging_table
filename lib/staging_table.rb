require "active_record"
require "staging_table/version"
require "staging_table/errors"
require "staging_table/configuration"
require "staging_table/session"
require "staging_table/model_factory"
require "staging_table/bulk_inserter"
require "staging_table/adapters/base"
require "staging_table/adapters/postgresql"
require "staging_table/adapters/mysql"
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

    def stage(source_model, **options, &block)
      session = Session.new(source_model, **options)
      session.create_table

      if block
        begin
          yield(session)
          session.transfer
        ensure
          session.drop_table
        end
      else
        session
      end
    end
  end
end
