require "spec_helper"

RSpec.describe StagingTable::Configuration do
  subject(:config) { described_class.new }

  describe "#default_batch_size" do
    it "defaults to 1000" do
      expect(config.default_batch_size).to eq(1000)
    end

    it "can be changed" do
      config.default_batch_size = 5000
      expect(config.default_batch_size).to eq(5000)
    end
  end

  describe "#default_transfer_strategy" do
    it "defaults to :insert" do
      expect(config.default_transfer_strategy).to eq(:insert)
    end

    it "can be changed" do
      config.default_transfer_strategy = :upsert
      expect(config.default_transfer_strategy).to eq(:upsert)
    end
  end
end

RSpec.describe StagingTable do
  describe ".configure" do
    after do
      # Reset configuration after each test
      StagingTable.instance_variable_set(:@configuration, nil)
    end

    it "yields the configuration object" do
      expect { |b| StagingTable.configure(&b) }.to yield_with_args(StagingTable::Configuration)
    end

    it "allows setting configuration options" do
      StagingTable.configure do |config|
        config.default_batch_size = 2000
        config.default_transfer_strategy = :upsert
      end

      expect(StagingTable.configuration.default_batch_size).to eq(2000)
      expect(StagingTable.configuration.default_transfer_strategy).to eq(:upsert)
    end
  end

  describe ".configuration" do
    it "returns the same configuration instance" do
      config1 = StagingTable.configuration
      config2 = StagingTable.configuration
      expect(config1).to be(config2)
    end
  end
end
