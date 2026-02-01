require "spec_helper"

RSpec.describe StagingTable::TransferStrategies::Upsert do
  shared_examples "upsert strategy" do
    let(:adapter) { StagingTable::Adapters::Base.for(ActiveRecord::Base.connection) }
    let(:temp_table_name) { "staging_test_#{SecureRandom.hex(8)}" }
    let(:staging_model) { StagingTable::ModelFactory.build(TestUser, temp_table_name, excluded_columns: %w[id]) }
    let(:inserter) { StagingTable::BulkInserter.new(staging_model) }

    before do
      adapter.create_table(temp_table_name, "test_users")
      TestUser.delete_all
    end

    after do
      adapter.drop_table(temp_table_name)
      TestUser.delete_all
    end

    describe "#transfer with :update action" do
      let(:strategy) do
        described_class.new(TestUser, staging_model, conflict_target: [:email], conflict_action: :update)
      end

      it "inserts new records" do
        records = [
          {name: "John", email: "john@example.com", age: 30}
        ]
        inserter.insert(records)

        strategy.transfer

        expect(TestUser.count).to eq(1)
        expect(TestUser.first.name).to eq("John")
      end

      it "updates existing records on conflict" do
        TestUser.create!(name: "Old John", email: "john@example.com", age: 25)

        records = [
          {name: "New John", email: "john@example.com", age: 35}
        ]
        inserter.insert(records)

        strategy.transfer

        expect(TestUser.count).to eq(1)
        user = TestUser.first
        expect(user.name).to eq("New John")
        expect(user.age).to eq(35)
      end

      it "handles mixed inserts and updates" do
        TestUser.create!(name: "Existing", email: "existing@example.com", age: 20)

        records = [
          {name: "Updated Existing", email: "existing@example.com", age: 21},
          {name: "Brand New", email: "new@example.com", age: 30}
        ]
        inserter.insert(records)

        strategy.transfer

        expect(TestUser.count).to eq(2)
        expect(TestUser.find_by(email: "existing@example.com").name).to eq("Updated Existing")
        expect(TestUser.find_by(email: "new@example.com").name).to eq("Brand New")
      end
    end

    describe "#transfer with :ignore action" do
      let(:strategy) do
        described_class.new(TestUser, staging_model, conflict_target: [:email], conflict_action: :ignore)
      end

      it "inserts new records" do
        records = [
          {name: "John", email: "john@example.com", age: 30}
        ]
        inserter.insert(records)

        strategy.transfer

        expect(TestUser.count).to eq(1)
        expect(TestUser.first.name).to eq("John")
      end

      it "ignores records that conflict" do
        TestUser.create!(name: "Original John", email: "john@example.com", age: 25)

        records = [
          {name: "New John", email: "john@example.com", age: 35}
        ]
        inserter.insert(records)

        strategy.transfer

        expect(TestUser.count).to eq(1)
        user = TestUser.first
        expect(user.name).to eq("Original John")
        expect(user.age).to eq(25)
      end

      it "handles mixed inserts and ignores" do
        TestUser.create!(name: "Existing", email: "existing@example.com", age: 20)

        records = [
          {name: "Should Be Ignored", email: "existing@example.com", age: 99},
          {name: "Brand New", email: "new@example.com", age: 30}
        ]
        inserter.insert(records)

        strategy.transfer

        expect(TestUser.count).to eq(2)
        expect(TestUser.find_by(email: "existing@example.com").name).to eq("Existing")
        expect(TestUser.find_by(email: "new@example.com").name).to eq("Brand New")
      end
    end
  end

  context "with PostgreSQL", :postgresql do
    include_examples "upsert strategy"
  end

  context "with MySQL", :mysql do
    include_examples "upsert strategy"
  end
end
