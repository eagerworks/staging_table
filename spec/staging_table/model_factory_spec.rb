# frozen_string_literal: true

require "spec_helper"

RSpec.describe StagingTable::ModelFactory do
  describe ".build" do
    let(:table_name) { "staging_test_users_#{SecureRandom.hex(8)}" }
    let(:model) { described_class.build(TestUser, table_name) }

    it "creates a class that inherits from the source model" do
      expect(model.superclass).to eq(TestUser)
    end

    it "sets the table name to the provided staging table name" do
      expect(model.table_name).to eq(table_name)
    end

    it "returns a model_name based on the source model" do
      expect(model.model_name.name).to eq("TestUser")
    end

    it "generates a descriptive class name" do
      expect(model.name).to include("TestUser")
      expect(model.name).to include("Staging_")
    end

    context "with excluded columns" do
      let(:model) { described_class.build(TestUser, table_name, excluded_columns: %w[created_at updated_at]) }

      it "sets the ignored columns" do
        expect(model.ignored_columns).to include("created_at", "updated_at")
      end
    end
  end
end
