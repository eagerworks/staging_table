# frozen_string_literal: true

module StagingTable
  # Holds statistics about a transfer operation
  class TransferResult
    attr_reader :inserted, :updated, :skipped, :total

    def initialize(inserted: 0, updated: 0, skipped: 0)
      @inserted = inserted
      @updated = updated
      @skipped = skipped
      @total = inserted + updated + skipped
    end

    def to_h
      {
        inserted: inserted,
        updated: updated,
        skipped: skipped,
        total: total
      }
    end

    def success?
      inserted > 0 || updated > 0
    end

    def empty?
      total.zero?
    end

    def inspect
      "#<StagingTable::TransferResult inserted=#{inserted} updated=#{updated} skipped=#{skipped} total=#{total}>"
    end
  end
end
