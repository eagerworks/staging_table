# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Extra Columns" do
  shared_examples "extra columns support" do
    let(:adapter) { StagingTable::Adapters::Base.for(ActiveRecord::Base.connection) }
    let(:temp_table_name) { "staging_test_#{SecureRandom.hex(8)}" }

    after do
      adapter.drop_table(temp_table_name)
    end

    describe "adding columns with simple type" do
      it "adds an integer column" do
        adapter.create_table(temp_table_name, "test_users", extra_columns: {priority: :integer})

        staging_model = StagingTable::ModelFactory.build(TestUser, temp_table_name)
        staging_model.reset_column_information

        expect(staging_model.column_names).to include("priority")
      end

      it "adds a string column" do
        adapter.create_table(temp_table_name, "test_users", extra_columns: {status: :string})

        staging_model = StagingTable::ModelFactory.build(TestUser, temp_table_name)
        staging_model.reset_column_information

        expect(staging_model.column_names).to include("status")
      end

      it "adds a boolean column" do
        adapter.create_table(temp_table_name, "test_users", extra_columns: {processed: :boolean})

        staging_model = StagingTable::ModelFactory.build(TestUser, temp_table_name)
        staging_model.reset_column_information

        expect(staging_model.column_names).to include("processed")
      end

      it "adds multiple columns" do
        adapter.create_table(temp_table_name, "test_users", extra_columns: {
          priority: :integer,
          status: :string,
          processed: :boolean
        })

        staging_model = StagingTable::ModelFactory.build(TestUser, temp_table_name)
        staging_model.reset_column_information

        expect(staging_model.column_names).to include("priority", "status", "processed")
      end
    end

    describe "adding columns with options" do
      it "adds a column with a default value" do
        adapter.create_table(temp_table_name, "test_users", extra_columns: {
          processed: {type: :boolean, default: false}
        })

        staging_model = StagingTable::ModelFactory.build(TestUser, temp_table_name)
        staging_model.reset_column_information

        expect(staging_model.column_names).to include("processed")

        # Insert a record without specifying the extra column
        inserter = StagingTable::BulkInserter.new(staging_model)
        inserter.insert([{name: "John", email: "john@example.com"}])

        record = staging_model.first
        expect([false, 0]).to include(record.processed) # SQLite stores as 0
      end

      it "adds an integer column with a default" do
        adapter.create_table(temp_table_name, "test_users", extra_columns: {
          priority: {type: :integer, default: 0}
        })

        staging_model = StagingTable::ModelFactory.build(TestUser, temp_table_name)
        staging_model.reset_column_information

        inserter = StagingTable::BulkInserter.new(staging_model)
        inserter.insert([{name: "John", email: "john@example.com"}])

        record = staging_model.first
        expect(record.priority).to eq(0)
      end
    end

    describe "querying extra columns" do
      it "can query on extra columns" do
        adapter.create_table(temp_table_name, "test_users", extra_columns: {
          priority: {type: :integer, default: 0}
        })

        staging_model = StagingTable::ModelFactory.build(TestUser, temp_table_name)
        staging_model.reset_column_information

        inserter = StagingTable::BulkInserter.new(staging_model)
        inserter.insert([
          {name: "John", email: "john@example.com", priority: 1},
          {name: "Jane", email: "jane@example.com", priority: 2},
          {name: "Bob", email: "bob@example.com", priority: 1}
        ])

        high_priority = staging_model.where(priority: 2)
        expect(high_priority.count).to eq(1)
        expect(high_priority.first.name).to eq("Jane")
      end

      it "can update extra columns" do
        adapter.create_table(temp_table_name, "test_users", extra_columns: {
          processed: {type: :boolean, default: false}
        })

        staging_model = StagingTable::ModelFactory.build(TestUser, temp_table_name)
        staging_model.reset_column_information

        inserter = StagingTable::BulkInserter.new(staging_model)
        inserter.insert([
          {name: "John", email: "john@example.com"},
          {name: "Jane", email: "jane@example.com"}
        ])

        # Update one record
        staging_model.where(name: "John").update_all(processed: true)

        john = staging_model.find_by(name: "John")
        jane = staging_model.find_by(name: "Jane")

        expect([true, 1]).to include(john.processed) # SQLite stores as 1
        expect([false, 0]).to include(jane.processed) # SQLite stores as 0
      end
    end

    describe "integration with StagingTable.stage" do
      before do
        TestUser.delete_all
      end

      it "creates staging table with extra columns" do
        result = StagingTable.stage(TestUser, extra_columns: {priority: :integer}) do |staging|
          staging.insert([
            {name: "John", email: "john@example.com", priority: 5}
          ])

          record = staging.first
          expect(record.priority).to eq(5)
        end

        expect(result).to be_a(StagingTable::TransferResult)
      end

      it "extra columns do not affect transfer to target" do
        result = StagingTable.stage(TestUser, extra_columns: {priority: :integer}) do |staging|
          staging.insert([
            {name: "Jane", email: "jane@example.com", priority: 5}
          ])
        end

        expect(result.inserted).to eq(1)
        user = TestUser.find_by(name: "Jane")
        expect(user).not_to be_nil
        expect(user.email).to eq("jane@example.com")
        # priority column doesn't exist on TestUser, should not cause error
      end

      it "omits extra columns from the transfer SQL" do
        executed_sql = []
        subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
          executed_sql << payload[:sql] if payload[:sql].is_a?(String)
        end

        begin
          StagingTable.stage(TestUser, extra_columns: {priority: :integer}) do |staging|
            staging.insert([{name: "Zed", email: "zed@example.com", priority: 9}])
          end
        ensure
          ActiveSupport::Notifications.unsubscribe(subscriber)
        end

        transfer_sql = executed_sql.find { |s| s.match?(/\AINSERT INTO .*test_users.*SELECT/m) }
        expect(transfer_sql).not_to be_nil
        expect(transfer_sql).not_to match(/\bpriority\b/i)
      end
    end

    describe "error handling" do
      it "raises ConfigurationError for unknown column types" do
        expect {
          adapter.create_table(temp_table_name, "test_users", extra_columns: {mystery: :wizard})
        }.to raise_error(StagingTable::ConfigurationError, /Unsupported column type/)
      end
    end
  end

  context "with PostgreSQL", :postgresql do
    include_examples "extra columns support"
  end

  context "with MySQL", :mysql do
    include_examples "extra columns support"
  end

  context "with SQLite", :sqlite do
    include_examples "extra columns support"
  end
end
