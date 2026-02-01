require "spec_helper"

RSpec.describe StagingTable::TransferResult do
  describe "#initialize" do
    it "defaults all counts to zero" do
      result = described_class.new

      expect(result.inserted).to eq(0)
      expect(result.updated).to eq(0)
      expect(result.skipped).to eq(0)
      expect(result.total).to eq(0)
    end

    it "accepts keyword arguments" do
      result = described_class.new(inserted: 10, updated: 5, skipped: 2)

      expect(result.inserted).to eq(10)
      expect(result.updated).to eq(5)
      expect(result.skipped).to eq(2)
    end

    it "calculates total from components" do
      result = described_class.new(inserted: 10, updated: 5, skipped: 2)

      expect(result.total).to eq(17)
    end
  end

  describe "#to_h" do
    it "returns a hash representation" do
      result = described_class.new(inserted: 10, updated: 5, skipped: 2)

      expect(result.to_h).to eq({
        inserted: 10,
        updated: 5,
        skipped: 2,
        total: 17
      })
    end
  end

  describe "#success?" do
    it "returns true when records were inserted" do
      result = described_class.new(inserted: 5)

      expect(result.success?).to be true
    end

    it "returns true when records were updated" do
      result = described_class.new(updated: 3)

      expect(result.success?).to be true
    end

    it "returns false when no records were inserted or updated" do
      result = described_class.new(skipped: 10)

      expect(result.success?).to be false
    end

    it "returns false for empty result" do
      result = described_class.new

      expect(result.success?).to be false
    end
  end

  describe "#empty?" do
    it "returns true when total is zero" do
      result = described_class.new

      expect(result.empty?).to be true
    end

    it "returns false when total is greater than zero" do
      result = described_class.new(inserted: 1)

      expect(result.empty?).to be false
    end
  end

  describe "#inspect" do
    it "returns a readable string representation" do
      result = described_class.new(inserted: 10, updated: 5, skipped: 2)

      expect(result.inspect).to eq("#<StagingTable::TransferResult inserted=10 updated=5 skipped=2 total=17>")
    end
  end
end
