# frozen_string_literal: true

require "spec_helper"

class EnumTestRecord < ActiveRecord::Base
  self.table_name = "enum_test_records"

  if ActiveRecord.gem_version >= Gem::Version.new("7.0")
    enum :foo, {bar: 2, baz: 3}
  else
    enum foo: {bar: 2, baz: 3}
  end
end

# Regression coverage for the bug where `Session#normalize_records` calls
# `attributes_before_type_cast` on AR objects, returning the *enum label*
# (e.g. "bar") instead of the underlying database integer (e.g. 2).
RSpec.describe "StagingTable with enum attributes" do
  shared_examples "preserves enum integer values" do
    let(:enum_values) do
      EnumTestRecord.defined_enums.fetch("foo").transform_values(&:to_i)
    end

    let(:session) do
      StagingTable::Session.new(EnumTestRecord)
    end

    before do
      ActiveRecord::Base.connection.create_table(EnumTestRecord.table_name, force: true) do |t|
        t.string :name
        t.string :email
        t.integer :foo
        t.timestamps null: true
      end
      EnumTestRecord.reset_column_information
    end

    after do
      session.drop_table if session.instance_variable_get(:@table_created)
      ActiveRecord::Base.connection.drop_table(EnumTestRecord.table_name, if_exists: true)
    end

    it "stages the enum's database integer, not the label, when given AR objects" do
      record = EnumTestRecord.new(
        id: 1,
        name: "Alice",
        email: "alice@example.com",
        foo: :bar
      )

      session.create_table

      expect { session.insert([record]) }.not_to raise_error

      raw_value = session.staging_model.connection.select_value(
        "SELECT foo FROM #{session.staging_model.table_name}"
      )

      expect(Integer(raw_value)).to eq(enum_values.fetch("bar"))
    end

    it "round-trips an enum value from AR object through staging into the source table" do
      original = EnumTestRecord.new(
        id: 2,
        name: "Bob",
        email: "bob@example.com",
        foo: :bar
      )

      session.create_table
      session.insert([original])
      result = session.transfer

      expect(result.inserted).to eq(1)
      expect(EnumTestRecord.count).to eq(1)
      expect(EnumTestRecord.first.foo).to eq("bar")
    end

    it "stages the enum integer when given an ActiveRecord::Relation" do
      EnumTestRecord.create!(name: "Carol", email: "carol@example.com", foo: :bar)
      EnumTestRecord.create!(name: "Dave", email: "dave@example.com", foo: :baz)

      session.create_table

      expect { session.insert(EnumTestRecord.all) }.not_to raise_error

      staged_values = session.staging_model.connection.select_values(
        "SELECT foo FROM #{session.staging_model.table_name} ORDER BY foo"
      ).map { |value| Integer(value) }

      expect(staged_values).to eq([
        enum_values.fetch("bar"),
        enum_values.fetch("baz")
      ])
    end

    it "still accepts plain hashes with the integer value" do
      session.create_table

      expect {
        session.insert([{
          name: "Eve",
          email: "eve@example.com",
          foo: enum_values.fetch("bar")
        }])
      }.not_to raise_error

      raw_value = session.staging_model.connection.select_value(
        "SELECT foo FROM #{session.staging_model.table_name}"
      )

      expect(Integer(raw_value)).to eq(enum_values.fetch("bar"))
    end
  end

  context "with PostgreSQL", :postgresql do
    include_examples "preserves enum integer values"
  end

  context "with MySQL", :mysql do
    include_examples "preserves enum integer values"
  end

  context "with SQLite", :sqlite do
    include_examples "preserves enum integer values"
  end
end
