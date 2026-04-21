# frozen_string_literal: true

require "spec_helper"

RSpec.describe StagingTable::ConflictResolver do
  let(:connection) { ActiveRecord::Base.connection }
  let(:table_name) { "staging_test" }
  let(:columns) { %w[id name email priority score] }

  describe "#enabled?" do
    it "returns false when options is nil" do
      resolver = described_class.new(connection, nil)
      expect(resolver.enabled?).to be false
    end

    it "returns false when options is empty" do
      resolver = described_class.new(connection, {})
      expect(resolver.enabled?).to be false
    end

    it "returns false when target is missing" do
      resolver = described_class.new(connection, {update: {priority: :greatest}})
      expect(resolver.enabled?).to be false
    end

    it "returns false when update is missing" do
      resolver = described_class.new(connection, {target: [:email]})
      expect(resolver.enabled?).to be false
    end

    it "returns true when both target and update are present" do
      resolver = described_class.new(connection, {target: [:email], update: {priority: :greatest}})
      expect(resolver.enabled?).to be true
    end
  end

  describe "validation" do
    it "raises error for invalid target type" do
      expect {
        described_class.new(connection, {target: "email", update: {priority: :greatest}})
      }.to raise_error(StagingTable::ConfigurationError, /target must be a symbol or array/)
    end

    it "raises error for invalid update type" do
      expect {
        described_class.new(connection, {target: [:email], update: "priority"})
      }.to raise_error(StagingTable::ConfigurationError, /update must be a hash/)
    end

    it "raises error for invalid strategy" do
      expect {
        described_class.new(connection, {target: [:email], update: {priority: :invalid}})
      }.to raise_error(StagingTable::ConfigurationError, /Invalid conflict resolution strategy: invalid/)
    end

    it "accepts valid symbol strategies" do
      valid_strategies = %i[greatest least new existing sum coalesce]
      valid_strategies.each do |strategy|
        expect {
          described_class.new(connection, {target: [:email], update: {priority: strategy}})
        }.not_to raise_error
      end
    end

    it "accepts raw SQL strings as strategies" do
      expect {
        described_class.new(connection, {target: [:email], update: {priority: "CUSTOM_FUNC(priority)"}})
      }.not_to raise_error
    end
  end

  shared_examples "conflict clause generation" do
    let(:adapter) { StagingTable::Adapters::Base.for(connection) }

    describe "#conflict_clause" do
      it "returns empty string when not enabled" do
        resolver = described_class.new(connection, nil)
        expect(resolver.conflict_clause(table_name)).to eq("")
      end

      it "generates clause with single target column" do
        resolver = described_class.new(connection, {
          target: [:email],
          update: {priority: :new}
        })
        clause = resolver.conflict_clause(table_name)
        expect(clause).to include("email")
      end

      it "generates clause with multiple target columns" do
        resolver = described_class.new(connection, {
          target: [:email, :name],
          update: {priority: :new}
        })
        clause = resolver.conflict_clause(table_name)
        expect(clause).to include("email")
        expect(clause).to include("name")
      end

      it "omits columns with :existing strategy from SET clause" do
        resolver = described_class.new(connection, {
          target: [:email],
          update: {priority: :existing, score: :new}
        })
        clause = resolver.conflict_clause(table_name)
        expect(clause).not_to include("priority")
        expect(clause).to include("score")
      end

      it "handles :greatest strategy" do
        resolver = described_class.new(connection, {
          target: [:email],
          update: {priority: :greatest}
        })
        clause = resolver.conflict_clause(table_name)
        expect(clause.downcase).to match(/greatest|max/)
        expect(clause).to include("priority")
      end

      it "handles :least strategy" do
        resolver = described_class.new(connection, {
          target: [:email],
          update: {priority: :least}
        })
        clause = resolver.conflict_clause(table_name)
        expect(clause.downcase).to match(/least|min/)
        expect(clause).to include("priority")
      end

      it "handles :new strategy" do
        resolver = described_class.new(connection, {
          target: [:email],
          update: {priority: :new}
        })
        clause = resolver.conflict_clause(table_name)
        expect(clause).to include("priority")
      end

      it "handles :sum strategy" do
        resolver = described_class.new(connection, {
          target: [:email],
          update: {score: :sum}
        })
        clause = resolver.conflict_clause(table_name)
        expect(clause).to include("+")
        expect(clause).to include("score")
      end

      it "handles :coalesce strategy" do
        resolver = described_class.new(connection, {
          target: [:email],
          update: {priority: :coalesce}
        })
        clause = resolver.conflict_clause(table_name)
        expect(clause.downcase).to include("coalesce")
        expect(clause).to include("priority")
      end

      it "passes through raw SQL strings" do
        resolver = described_class.new(connection, {
          target: [:email],
          update: {priority: "CUSTOM_FUNC(priority, 10)"}
        })
        clause = resolver.conflict_clause(table_name)
        expect(clause).to include("CUSTOM_FUNC(priority, 10)")
      end

      it "handles multiple update columns" do
        resolver = described_class.new(connection, {
          target: [:email],
          update: {
            priority: :greatest,
            score: :least,
            name: :new
          }
        })
        clause = resolver.conflict_clause(table_name)
        expect(clause).to include("priority")
        expect(clause).to include("score")
        expect(clause).to include("name")
      end
    end
  end

  context "with PostgreSQL", :postgresql do
    include_examples "conflict clause generation"

    it "generates PostgreSQL-specific ON CONFLICT syntax" do
      resolver = described_class.new(connection, {
        target: [:email],
        update: {priority: :new}
      })
      clause = resolver.conflict_clause(table_name)
      expect(clause).to include("ON CONFLICT")
      expect(clause).to include("DO UPDATE SET")
      expect(clause).to include("EXCLUDED")
    end

    it "generates DO NOTHING when all columns use :existing" do
      resolver = described_class.new(connection, {
        target: [:email],
        update: {priority: :existing}
      })
      clause = resolver.conflict_clause(table_name)
      expect(clause).to include("DO NOTHING")
    end
  end

  context "with MySQL", :mysql do
    # MySQL uses ON DUPLICATE KEY which doesn't explicitly name target columns
    # so we skip the shared examples that check for target column presence
    let(:adapter) { StagingTable::Adapters::Base.for(connection) }

    describe "#conflict_clause" do
      it "returns empty string when not enabled" do
        resolver = described_class.new(connection, nil)
        expect(resolver.conflict_clause(table_name)).to eq("")
      end

      it "omits columns with :existing strategy from SET clause" do
        resolver = described_class.new(connection, {
          target: [:email],
          update: {priority: :existing, score: :new}
        })
        clause = resolver.conflict_clause(table_name)
        expect(clause).not_to include("priority")
        expect(clause).to include("score")
      end

      it "handles :greatest strategy" do
        resolver = described_class.new(connection, {
          target: [:email],
          update: {priority: :greatest}
        })
        clause = resolver.conflict_clause(table_name)
        expect(clause.downcase).to include("greatest")
        expect(clause).to include("priority")
      end

      it "handles :least strategy" do
        resolver = described_class.new(connection, {
          target: [:email],
          update: {priority: :least}
        })
        clause = resolver.conflict_clause(table_name)
        expect(clause.downcase).to include("least")
        expect(clause).to include("priority")
      end

      it "handles :new strategy" do
        resolver = described_class.new(connection, {
          target: [:email],
          update: {priority: :new}
        })
        clause = resolver.conflict_clause(table_name)
        expect(clause).to include("priority")
      end

      it "handles :sum strategy" do
        resolver = described_class.new(connection, {
          target: [:email],
          update: {score: :sum}
        })
        clause = resolver.conflict_clause(table_name)
        expect(clause).to include("+")
        expect(clause).to include("score")
      end

      it "handles :coalesce strategy" do
        resolver = described_class.new(connection, {
          target: [:email],
          update: {priority: :coalesce}
        })
        clause = resolver.conflict_clause(table_name)
        expect(clause.downcase).to include("coalesce")
        expect(clause).to include("priority")
      end

      it "passes through raw SQL strings" do
        resolver = described_class.new(connection, {
          target: [:email],
          update: {priority: "CUSTOM_FUNC(priority, 10)"}
        })
        clause = resolver.conflict_clause(table_name)
        expect(clause).to include("CUSTOM_FUNC(priority, 10)")
      end

      it "handles multiple update columns" do
        resolver = described_class.new(connection, {
          target: [:email],
          update: {
            priority: :greatest,
            score: :least,
            name: :new
          }
        })
        clause = resolver.conflict_clause(table_name)
        expect(clause).to include("priority")
        expect(clause).to include("score")
        expect(clause).to include("name")
      end
    end

    it "generates MySQL-specific ON DUPLICATE KEY syntax" do
      resolver = described_class.new(connection, {
        target: [:email],
        update: {priority: :new}
      })
      clause = resolver.conflict_clause(table_name)
      expect(clause).to include("ON DUPLICATE KEY UPDATE")
      expect(clause).to include("VALUES")
    end

    it "emits a no-op assignment when all columns use :existing" do
      # MySQL has no DO NOTHING, so we assign the target column to itself to
      # silently ignore the duplicate row instead of raising RecordNotUnique.
      resolver = described_class.new(connection, {
        target: [:email],
        update: {priority: :existing}
      })
      clause = resolver.conflict_clause(table_name)
      expect(clause).to include("ON DUPLICATE KEY UPDATE")
      expect(clause).to match(/`email`\s*=\s*`email`/)
    end
  end

  context "with SQLite", :sqlite do
    include_examples "conflict clause generation"

    it "generates SQLite-specific ON CONFLICT syntax" do
      resolver = described_class.new(connection, {
        target: [:email],
        update: {priority: :new}
      })
      clause = resolver.conflict_clause(table_name)
      expect(clause).to include("ON CONFLICT")
      expect(clause).to include("DO UPDATE SET")
      expect(clause.downcase).to include("excluded")
    end

    it "generates DO NOTHING when all columns use :existing" do
      resolver = described_class.new(connection, {
        target: [:email],
        update: {priority: :existing}
      })
      clause = resolver.conflict_clause(table_name)
      expect(clause).to include("DO NOTHING")
    end
  end
end
