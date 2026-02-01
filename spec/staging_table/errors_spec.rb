require "spec_helper"

RSpec.describe "StagingTable Error Handling" do
  let(:model) { TestUser }
  let(:session) { StagingTable::Session.new(model) }

  describe StagingTable::TableError do
    it "is raised when inserting without creating table" do
      expect {
        session.insert([{ name: "Test" }])
      }.to raise_error(StagingTable::TableError, /Staging table has not been created/)
    end

    it "is raised when transferring without creating table" do
      expect {
        session.transfer
      }.to raise_error(StagingTable::TableError, /Staging table has not been created/)
    end
  end

  describe StagingTable::ConfigurationError do
    it "is raised for invalid transfer strategy" do
      session = StagingTable::Session.new(model, transfer_strategy: :invalid_strategy)
      allow(session).to receive(:ensure_table_created!)

      expect {
        session.transfer
      }.to raise_error(StagingTable::ConfigurationError, /Invalid transfer strategy/)
    end

    it "is raised for postgresql upsert without conflict_target" do
      # Mock postgresql connection
      connection = double("Connection", adapter_name: "PostgreSQL")
      allow(model).to receive(:connection).and_return(connection)
      
      # Mock staging model
      staging_model = double("StagingModel", table_name: "staging_users", column_names: ["id", "name"])
      
      strategy = StagingTable::TransferStrategies::Upsert.new(model, staging_model, transfer_strategy: :upsert)
      
      expect {
        strategy.transfer
      }.to raise_error(StagingTable::ConfigurationError, /PostgreSQL upsert requires :conflict_target/)
    end
  end

  describe StagingTable::AdapterError do
    it "is raised for unsupported adapter" do
      connection = double("Connection", adapter_name: "SQLite")
      
      expect {
        StagingTable::Adapters::Base.for(connection)
      }.to raise_error(StagingTable::AdapterError, /Unsupported adapter: sqlite/)
    end

    it "is raised for upsert with unsupported adapter" do
      connection = double("Connection", adapter_name: "SQLite")
      allow(model).to receive(:connection).and_return(connection)
      staging_model = double("StagingModel")
      
      strategy = StagingTable::TransferStrategies::Upsert.new(model, staging_model)
      
      expect {
        strategy.transfer
      }.to raise_error(StagingTable::AdapterError, /Upsert strategy not supported for adapter/)
    end
  end

  describe StagingTable::RecordError do
    it "is raised for invalid record format" do
      inserter = StagingTable::BulkInserter.new(double("Model"))
      
      expect {
        inserter.insert(["not a hash"])
      }.to raise_error(StagingTable::RecordError, /All records must be hashes/)
    end
  end

  describe "Error Inheritance" do
    it "all errors inherit from StagingTable::Error" do
      expect(StagingTable::ConfigurationError.ancestors).to include(StagingTable::Error)
      expect(StagingTable::AdapterError.ancestors).to include(StagingTable::Error)
      expect(StagingTable::TableError.ancestors).to include(StagingTable::Error)
      expect(StagingTable::TransferError.ancestors).to include(StagingTable::Error)
      expect(StagingTable::RecordError.ancestors).to include(StagingTable::Error)
    end

    it "StagingTable::Error inherits from StandardError" do
      expect(StagingTable::Error.ancestors).to include(StandardError)
    end
  end
end
