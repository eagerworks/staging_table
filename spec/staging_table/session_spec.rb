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

      it "accepts an array of ActiveRecord objects" do
        TestUser.create!(name: "John", email: "john@example.com")
        TestUser.create!(name: "Jane", email: "jane@example.com")

        session.insert(TestUser.all.to_a)

        expect(session.staging_model.count).to eq(2)
        expect(session.staging_model.pluck(:name)).to match_array(%w[John Jane])
      end

      it "accepts an ActiveRecord::Relation" do
        TestUser.create!(name: "John", email: "john@example.com")
        TestUser.create!(name: "Jane", email: "jane@example.com")
        TestUser.create!(name: "Bob", email: "bob@example.com")

        session.insert(TestUser.where(name: %w[John Jane]))

        expect(session.staging_model.count).to eq(2)
        expect(session.staging_model.pluck(:name)).to match_array(%w[John Jane])
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

      it "returns a TransferResult with statistics" do
        session.insert([
          {name: "John", email: "john@example.com"},
          {name: "Jane", email: "jane@example.com"}
        ])

        result = session.transfer

        expect(result).to be_a(StagingTable::TransferResult)
        expect(result.inserted).to eq(2)
        expect(result.total).to eq(2)
      end

      it "returns an empty TransferResult when no records staged" do
        result = session.transfer

        expect(result).to be_a(StagingTable::TransferResult)
        expect(result.empty?).to be true
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

    describe "callbacks" do
      it "calls before_insert callback" do
        callback_called = false
        session_with_callback = described_class.new(TestUser,
          before_insert: ->(s) { callback_called = true })
        session_with_callback.create_table

        session_with_callback.insert([{name: "John", email: "john@example.com"}])

        expect(callback_called).to be true
        session_with_callback.drop_table
      end

      it "calls after_insert callback with session and records" do
        received_args = nil
        session_with_callback = described_class.new(TestUser,
          after_insert: ->(s, records) { received_args = [s, records] })
        session_with_callback.create_table

        session_with_callback.insert([{name: "John", email: "john@example.com"}])

        expect(received_args).not_to be_nil
        expect(received_args[0]).to eq(session_with_callback)
        expect(received_args[1]).to be_an(Array)
        # Records can have string or symbol keys depending on source
        record = received_args[1].first
        expect(record[:name] || record["name"]).to eq("John")
        session_with_callback.drop_table
      end

      it "calls before_transfer callback" do
        callback_called = false
        session_with_callback = described_class.new(TestUser,
          before_transfer: ->(s) { callback_called = true })
        session_with_callback.create_table
        session_with_callback.insert([{name: "John", email: "john@example.com"}])

        session_with_callback.transfer

        expect(callback_called).to be true
        session_with_callback.drop_table
      end

      it "calls after_transfer callback with session and result" do
        received_args = nil
        session_with_callback = described_class.new(TestUser,
          after_transfer: ->(s, result) { received_args = [s, result] })
        session_with_callback.create_table
        session_with_callback.insert([{name: "John", email: "john@example.com"}])

        session_with_callback.transfer

        expect(received_args).not_to be_nil
        expect(received_args[0]).to eq(session_with_callback)
        expect(received_args[1]).to be_a(StagingTable::TransferResult)
        expect(received_args[1].inserted).to eq(1)
        session_with_callback.drop_table
      end

      it "allows modifying staged data in before_transfer callback" do
        session_with_callback = described_class.new(TestUser,
          before_transfer: ->(s) { s.where(name: "Invalid").delete_all })
        session_with_callback.create_table
        session_with_callback.insert([
          {name: "John", email: "john@example.com"},
          {name: "Invalid", email: "invalid@example.com"}
        ])

        result = session_with_callback.transfer

        expect(TestUser.count).to eq(1)
        expect(TestUser.first.name).to eq("John")
        expect(result.inserted).to eq(1)
        session_with_callback.drop_table
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

  context "with SQLite", :sqlite do
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
end
