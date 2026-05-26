# frozen_string_literal: true

require "spec_helper"

RSpec.describe "insert_on_conflict end-to-end" do
  shared_examples "staging insert conflict resolution" do
    before do
      TestUser.delete_all
    end

    it "applies :greatest/:sum/:new/:existing strategies across batches" do
      StagingTable.stage(
        TestUser,
        include_indexes: true,
        extra_columns: {priority: :integer, score: :integer},
        insert_on_conflict: {
          target: [:email],
          update: {
            priority: :greatest,
            score: :sum,
            name: :new,
            age: :existing
          }
        }
      ) do |staging|
        staging.insert([
          {email: "john@example.com", name: "John", age: 30, priority: 1, score: 10}
        ])

        staging.insert([
          {email: "john@example.com", name: "Johnny", age: 99, priority: 5, score: 20}
        ])

        record = staging.find_by(email: "john@example.com")
        expect(record.priority).to eq(5)       # greatest
        expect(record.score).to eq(30)         # sum
        expect(record.name).to eq("Johnny")    # new
        expect(record.age).to eq(30)           # existing (first write wins)
      end
    end

    it "emits DO NOTHING / no SET clause when every column is :existing" do
      StagingTable.stage(
        TestUser,
        include_indexes: true,
        insert_on_conflict: {
          target: [:email],
          update: {name: :existing}
        }
      ) do |staging|
        staging.insert([{email: "a@example.com", name: "First"}])
        staging.insert([{email: "a@example.com", name: "Second"}])

        record = staging.find_by(email: "a@example.com")
        expect(record.name).to eq("First")
      end
    end
  end

  context "with PostgreSQL", :postgresql do
    include_examples "staging insert conflict resolution"
  end

  # MySQL ON DUPLICATE KEY fires on any unique constraint, which matches the
  # test_users email index — same behavior surface from the user's perspective.
  context "with MySQL", :mysql do
    include_examples "staging insert conflict resolution"
  end

  context "with SQLite", :sqlite do
    include_examples "staging insert conflict resolution"
  end
end
