require "spec_helper"

RSpec.describe StagingTable::TransferStrategies::Insert do
  shared_examples "insert strategy" do
    let(:adapter) { StagingTable::Adapters::Base.for(ActiveRecord::Base.connection) }
    let(:temp_table_name) { "staging_test_#{SecureRandom.hex(8)}" }
    let(:staging_model) { StagingTable::ModelFactory.build(TestUser, temp_table_name, excluded_columns: %w[id]) }
    let(:strategy) { described_class.new(TestUser, staging_model) }
    let(:inserter) { StagingTable::BulkInserter.new(staging_model) }

    before do
      adapter.create_table(temp_table_name, "test_users")
      TestUser.delete_all
    end

    after do
      adapter.drop_table(temp_table_name)
      TestUser.delete_all
    end

    describe "#transfer" do
      it "transfers all records from staging to source table" do
        records = [
          {name: "John", email: "john@example.com", age: 30},
          {name: "Jane", email: "jane@example.com", age: 25}
        ]
        inserter.insert(records)

        strategy.transfer

        expect(TestUser.count).to eq(2)
        expect(TestUser.pluck(:name)).to match_array(%w[John Jane])
      end

      it "preserves data integrity during transfer" do
        records = [
          {name: "John", email: "john@example.com", age: 30, active: true}
        ]
        inserter.insert(records)

        strategy.transfer

        user = TestUser.find_by(email: "john@example.com")
        expect(user.name).to eq("John")
        expect(user.age).to eq(30)
        expect(user.active).to be true
      end

      it "transfers empty staging table without error" do
        expect { strategy.transfer }.not_to raise_error
        expect(TestUser.count).to eq(0)
      end
    end
  end

  context "with PostgreSQL", :postgresql do
    include_examples "insert strategy"
  end

  context "with MySQL", :mysql do
    include_examples "insert strategy"
  end
end
