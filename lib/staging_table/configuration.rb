# frozen_string_literal: true

module StagingTable
  class Configuration
    attr_accessor :default_batch_size, :default_transfer_strategy

    def initialize
      @default_batch_size = 1000
      @default_transfer_strategy = :insert
    end
  end
end
