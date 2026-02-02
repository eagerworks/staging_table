# frozen_string_literal: true

require "spec_helper"

RSpec.describe StagingTable::Adapters::Sqlite, :sqlite do
  let(:connection) { ActiveRecord::Base.connection }
  let(:adapter) { described_class.new(connection) }
  let(:temp_table_name) { "staging_test_#{SecureRandom.hex(8)}" }

  after do
    connection.execute("DROP TABLE IF EXISTS #{temp_table_name}")
  end

  describe "#create_table" do
    it "creates a table with the same structure as the source" do
      adapter.create_table(temp_table_name, "test_users")

      expect(connection.table_exists?(temp_table_name)).to be true

      source_columns = connection.columns("test_users").map(&:name)
      temp_columns = connection.columns(temp_table_name).map(&:name)

      expect(temp_columns).to match_array(source_columns)
    end

    it "includes indexes when requested" do
      adapter.create_table(temp_table_name, "test_users", include_indexes: true)

      indexes = connection.indexes(temp_table_name)
      expect(indexes).not_to be_empty
    end

    it "excludes indexes by default" do
      adapter.create_table(temp_table_name, "test_users")

      indexes = connection.indexes(temp_table_name)
      expect(indexes).to be_empty
    end
  end

  describe "#drop_table" do
    it "drops an existing table" do
      adapter.create_table(temp_table_name, "test_users")
      expect(connection.table_exists?(temp_table_name)).to be true

      adapter.drop_table(temp_table_name)
      expect(connection.table_exists?(temp_table_name)).to be false
    end

    it "does not raise an error if the table does not exist" do
      expect { adapter.drop_table("nonexistent_table_#{SecureRandom.hex(8)}") }.not_to raise_error
    end
  end
end

RSpec.describe StagingTable::Adapters::Base, :sqlite do
  describe ".for" do
    it "returns a Sqlite adapter for sqlite connections" do
      adapter = described_class.for(ActiveRecord::Base.connection)
      expect(adapter).to be_a(StagingTable::Adapters::Sqlite)
    end
  end
end
