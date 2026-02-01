require "spec_helper"

RSpec.describe StagingTable::Session do
  shared_examples "session" do
    let(:session) { described_class.new(TestUser) }

    before do
      TestUser.delete_all
    end

    after do
      session.drop_table if session.instance_variable_get(:@table_created)
      TestUser.delete_all
    end

    describe "#create_table" do
      it "creates a staging table" do
        session.create_table

        expect(session.staging_model).not_to be_nil
        expect(ActiveRecord::Base.connection.table_exists?(session.staging_model.table_name)).to be true
      end

      it "only creates the table once" do
        session.create_table
        first_table_name = session.staging_model.table_name

        session.create_table
        expect(session.staging_model.table_name).to eq(first_table_name)
      end
    end

    describe "#drop_table" do
      it "drops the staging table" do
        session.create_table
        table_name = session.staging_model.table_name

        session.drop_table

        expect(ActiveRecord::Base.connection.table_exists?(table_name)).to be false
      end

      it "does nothing if table was never created" do
        expect { session.drop_table }.not_to raise_error
      end
    end

    describe "#insert" do
      before { session.create_table }

      it "inserts records into the staging table" do
        records = [
          {name: "John", email: "john@example.com"},
          {name: "Jane", email: "jane@example.com"}
        ]

        session.insert(records)

        expect(session.staging_model.count).to eq(2)
      end

      it "raises an error if table not created" do
        new_session = described_class.new(TestUser)
        expect { new_session.insert([{name: "Test"}]) }.to raise_error(StagingTable::Error)
      end
    end

    describe "#transfer" do
      before { session.create_table }

      it "transfers data from staging to source table" do
        session.insert([{name: "John", email: "john@example.com"}])

        session.transfer

        expect(TestUser.count).to eq(1)
        expect(TestUser.first.name).to eq("John")
      end
    end

    describe "method delegation to staging_model" do
      before { session.create_table }

      it "delegates ActiveRecord query methods to the staging model" do
        session.insert([
          {name: "John", email: "john@example.com"},
          {name: "Jane", email: "jane@example.com"}
        ])

        expect(session.count).to eq(2)
        expect(session.where(name: "John").count).to eq(1)
        expect(session.pluck(:name)).to match_array(%w[John Jane])
      end
    end
  end

  context "with PostgreSQL", :postgresql do
    include_examples "session"

    describe "with options" do
      it "respects excluded_columns option" do
        session = described_class.new(TestUser, excluded_columns: %w[created_at updated_at])
        session.create_table

        expect(session.staging_model.ignored_columns).to include("created_at", "updated_at")

        session.drop_table
      end

      it "respects transfer_strategy option" do
        TestUser.delete_all
        TestUser.create!(name: "Existing", email: "test@example.com")

        session = described_class.new(TestUser,
          excluded_columns: %w[id],
          transfer_strategy: :upsert,
          conflict_target: [:email],
          conflict_action: :update)
        session.create_table
        session.insert([{name: "Updated", email: "test@example.com"}])
        session.transfer

        expect(TestUser.count).to eq(1)
        expect(TestUser.first.name).to eq("Updated")

        session.drop_table
        TestUser.delete_all
      end
    end
  end

  context "with MySQL", :mysql do
    include_examples "session"
  end
end
