require "spec_helper"

RSpec.describe StagingTable do
  shared_examples "staging table integration" do
    before do
      TestUser.delete_all
    end

    after do
      TestUser.delete_all
      # Clean up any leftover staging tables
      staging_tables = ActiveRecord::Base.connection.tables.select { |t| t.start_with?("staging_") }
      staging_tables.each do |table|
        ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS #{table}")
      end
    end

    describe ".stage with block" do
      it "creates and drops the staging table automatically" do
        staging_table_name = nil

        described_class.stage(TestUser) do |staging|
          staging_table_name = staging.staging_model.table_name
          expect(ActiveRecord::Base.connection.table_exists?(staging_table_name)).to be true
        end

        expect(ActiveRecord::Base.connection.table_exists?(staging_table_name)).to be false
      end

      it "transfers data at the end of the block" do
        described_class.stage(TestUser) do |staging|
          staging.insert([
            {name: "John", email: "john@example.com"},
            {name: "Jane", email: "jane@example.com"}
          ])
        end

        expect(TestUser.count).to eq(2)
      end

      it "cleans up even if an error is raised" do
        staging_table_name = nil

        expect do
          described_class.stage(TestUser) do |staging|
            staging_table_name = staging.staging_model.table_name
            raise StandardError, "Something went wrong"
          end
        end.to raise_error(StandardError, "Something went wrong")

        expect(ActiveRecord::Base.connection.table_exists?(staging_table_name)).to be false
      end

      it "does not transfer data if an error is raised" do
        expect do
          described_class.stage(TestUser) do |staging|
            staging.insert([{name: "John", email: "john@example.com"}])
            raise StandardError, "Something went wrong"
          end
        end.to raise_error(StandardError)

        expect(TestUser.count).to eq(0)
      end
    end

    describe ".stage without block" do
      it "returns a session for manual control" do
        session = described_class.stage(TestUser)

        expect(session).to be_a(StagingTable::Session)
        expect(session.staging_model).not_to be_nil

        session.drop_table
      end
    end

    describe "full workflow with upsert" do
      it "handles a complete upsert workflow" do
        # Create some existing records
        TestUser.create!(name: "Existing User", email: "existing@example.com", age: 25)

        described_class.stage(TestUser,
          excluded_columns: %w[id],
          transfer_strategy: :upsert,
          conflict_target: [:email],
          conflict_action: :update) do |staging|
          staging.insert([
            {name: "Updated Existing", email: "existing@example.com", age: 30},
            {name: "Brand New User", email: "new@example.com", age: 22}
          ])
        end

        expect(TestUser.count).to eq(2)
        expect(TestUser.find_by(email: "existing@example.com").name).to eq("Updated Existing")
        expect(TestUser.find_by(email: "existing@example.com").age).to eq(30)
        expect(TestUser.find_by(email: "new@example.com").name).to eq("Brand New User")
      end
    end

    describe "large batch insert" do
      it "handles inserting many records" do
        records = 100.times.map do |i|
          {name: "User #{i}", email: "user#{i}@example.com", age: 20 + (i % 50)}
        end

        described_class.stage(TestUser, batch_size: 25) do |staging|
          staging.insert(records)
          expect(staging.count).to eq(100)
        end

        expect(TestUser.count).to eq(100)
      end
    end
  end

  context "with PostgreSQL", :postgresql do
    include_examples "staging table integration"
  end

  context "with MySQL", :mysql do
    include_examples "staging table integration"
  end

  context "with SQLite", :sqlite do
    include_examples "staging table integration"
  end
end
