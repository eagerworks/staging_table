require "spec_helper"

RSpec.describe StagingTable::BulkInserter do
  shared_examples "bulk inserter" do
    let(:adapter) { StagingTable::Adapters::Base.for(ActiveRecord::Base.connection) }
    let(:temp_table_name) { "staging_test_#{SecureRandom.hex(8)}" }
    let(:staging_model) { StagingTable::ModelFactory.build(TestUser, temp_table_name) }
    let(:inserter) { described_class.new(staging_model, batch_size: 2) }

    before do
      adapter.create_table(temp_table_name, "test_users")
    end

    after do
      adapter.drop_table(temp_table_name)
    end

    describe "#insert" do
      it "inserts records into the staging table" do
        records = [
          {name: "John", email: "john@example.com", age: 30},
          {name: "Jane", email: "jane@example.com", age: 25}
        ]

        inserter.insert(records)

        expect(staging_model.count).to eq(2)
        expect(staging_model.pluck(:name)).to match_array(%w[John Jane])
      end

      it "handles empty records array" do
        expect { inserter.insert([]) }.not_to raise_error
        expect(staging_model.count).to eq(0)
      end

      it "handles nil values" do
        records = [
          {name: "John", email: "john@example.com", age: nil}
        ]

        inserter.insert(records)

        user = staging_model.first
        expect(user.name).to eq("John")
        expect(user.age).to be_nil
      end

      it "respects batch size" do
        records = [
          {name: "User1", email: "user1@example.com"},
          {name: "User2", email: "user2@example.com"},
          {name: "User3", email: "user3@example.com"},
          {name: "User4", email: "user4@example.com"},
          {name: "User5", email: "user5@example.com"}
        ]

        # With batch_size of 2, this should result in 3 INSERT statements
        inserter.insert(records)

        expect(staging_model.count).to eq(5)
      end

      it "handles boolean values" do
        records = [
          {name: "Active", email: "active@example.com", active: true},
          {name: "Inactive", email: "inactive@example.com", active: false}
        ]

        inserter.insert(records)

        expect(staging_model.find_by(name: "Active").active).to be true
        expect(staging_model.find_by(name: "Inactive").active).to be false
      end

      it "handles timestamp values" do
        now = Time.current
        records = [
          {name: "John", email: "john@example.com", created_at: now, updated_at: now}
        ]

        inserter.insert(records)

        user = staging_model.first
        expect(user.created_at).to be_within(1.second).of(now)
      end
    end
  end

  context "with PostgreSQL", :postgresql do
    include_examples "bulk inserter"
  end

  context "with MySQL", :mysql do
    include_examples "bulk inserter"
  end
end
