# frozen_string_literal: true

require "active_support/notifications"

module StagingTable
  # Provides ActiveSupport::Notifications instrumentation for StagingTable operations.
  #
  # Available events:
  #   - staging_table.create_table  - When a staging table is created
  #   - staging_table.drop_table    - When a staging table is dropped
  #   - staging_table.insert        - When records are inserted into staging
  #   - staging_table.transfer      - When data is transferred to target table
  #   - staging_table.stage         - Wraps the entire staging block operation
  #
  # Example:
  #   ActiveSupport::Notifications.subscribe('staging_table.transfer') do |event|
  #     Rails.logger.info "Transfer completed in #{event.duration}ms"
  #     StatsD.measure('staging_table.transfer.duration', event.duration)
  #   end
  #
  module Instrumentation
    NAMESPACE = "staging_table"

    EVENTS = %i[
      create_table
      drop_table
      insert
      transfer
      stage
    ].freeze

    class << self
      # Instruments a block with the given event name.
      #
      # @param event_name [Symbol] The event name (without namespace)
      # @param payload [Hash] Additional payload data
      # @yield The block to instrument
      # @return The result of the block
      def instrument(event_name, payload = {}, &block)
        full_event_name = "#{NAMESPACE}.#{event_name}"
        ActiveSupport::Notifications.instrument(full_event_name, payload, &block)
      end

      # Subscribe to a StagingTable event.
      #
      # @param event_name [Symbol, String] Event name (with or without namespace)
      # @yield [event] Block called for each event
      # @yieldparam event [ActiveSupport::Notifications::Event]
      # @return [ActiveSupport::Notifications::Fanout::Subscribers::Evented]
      def subscribe(event_name, &block)
        full_name = event_name.to_s.start_with?(NAMESPACE) ? event_name : "#{NAMESPACE}.#{event_name}"
        ActiveSupport::Notifications.subscribe(full_name, &block)
      end

      # Unsubscribe from a StagingTable event.
      #
      # @param subscriber [Object] The subscriber to remove
      def unsubscribe(subscriber)
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end

      # Subscribe to all StagingTable events.
      #
      # @yield [event] Block called for each event
      # @return [ActiveSupport::Notifications::Fanout::Subscribers::Evented]
      def subscribe_all(&block)
        ActiveSupport::Notifications.subscribe(/^#{NAMESPACE}\./, &block)
      end
    end
  end
end
