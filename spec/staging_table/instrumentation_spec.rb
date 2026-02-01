require "spec_helper"

RSpec.describe StagingTable::Instrumentation do
  describe ".instrument" do
    it "instruments a block with the namespaced event name" do
      events = []
      subscriber = ActiveSupport::Notifications.subscribe("staging_table.test_event") do |event|
        events << event
      end

      described_class.instrument(:test_event, {foo: "bar"}) do
        # do nothing
      end

      expect(events.size).to eq(1)
      expect(events.first.name).to eq("staging_table.test_event")
      expect(events.first.payload[:foo]).to eq("bar")

      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    it "returns the result of the block" do
      result = described_class.instrument(:test_event) { 42 }
      expect(result).to eq(42)
    end

    it "allows modifying payload within the block" do
      events = []
      subscriber = ActiveSupport::Notifications.subscribe("staging_table.test_event") do |event|
        events << event
      end

      described_class.instrument(:test_event, {initial: true}) do |payload|
        payload[:added] = "value"
      end

      expect(events.first.payload[:initial]).to be true
      expect(events.first.payload[:added]).to eq("value")

      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
  end

  describe ".subscribe" do
    it "subscribes to events with just the event name" do
      events = []
      subscriber = described_class.subscribe(:test_event) do |event|
        events << event
      end

      described_class.instrument(:test_event)

      expect(events.size).to eq(1)

      described_class.unsubscribe(subscriber)
    end

    it "subscribes to events with full namespaced name" do
      events = []
      subscriber = described_class.subscribe("staging_table.test_event") do |event|
        events << event
      end

      described_class.instrument(:test_event)

      expect(events.size).to eq(1)

      described_class.unsubscribe(subscriber)
    end
  end

  describe ".subscribe_all" do
    it "subscribes to all staging_table events" do
      events = []
      subscriber = described_class.subscribe_all do |event|
        events << event
      end

      described_class.instrument(:event_one)
      described_class.instrument(:event_two)

      expect(events.size).to eq(2)
      expect(events.map(&:name)).to contain_exactly("staging_table.event_one", "staging_table.event_two")

      described_class.unsubscribe(subscriber)
    end
  end

  describe ".unsubscribe" do
    it "removes a subscriber" do
      events = []
      subscriber = described_class.subscribe(:test_event) do |event|
        events << event
      end

      described_class.instrument(:test_event)
      expect(events.size).to eq(1)

      described_class.unsubscribe(subscriber)

      described_class.instrument(:test_event)
      expect(events.size).to eq(1) # No new events
    end
  end
end

RSpec.describe "StagingTable instrumentation integration", :sqlite do
  before do
    TestUser.delete_all
  end

  after do
    TestUser.delete_all
  end

  describe "staging_table.stage event" do
    it "instruments the entire staging block" do
      events = []
      subscriber = StagingTable::Instrumentation.subscribe(:stage) do |event|
        events << event
      end

      StagingTable.stage(TestUser) do |staging|
        staging.insert([{name: "John", email: "john@example.com"}])
      end

      expect(events.size).to eq(1)
      event = events.first
      expect(event.payload[:source_model]).to eq(TestUser)
      expect(event.payload[:source_table]).to eq("test_users")
      expect(event.payload[:result]).to be_a(StagingTable::TransferResult)
      expect(event.duration).to be > 0

      StagingTable::Instrumentation.unsubscribe(subscriber)
    end
  end

  describe "staging_table.create_table event" do
    it "instruments table creation" do
      events = []
      subscriber = StagingTable::Instrumentation.subscribe(:create_table) do |event|
        events << event
      end

      session = StagingTable::Session.new(TestUser)
      session.create_table

      expect(events.size).to eq(1)
      event = events.first
      expect(event.payload[:source_model]).to eq(TestUser)
      expect(event.payload[:staging_table]).to start_with("staging_test_users_")

      session.drop_table
      StagingTable::Instrumentation.unsubscribe(subscriber)
    end
  end

  describe "staging_table.drop_table event" do
    it "instruments table dropping" do
      events = []
      subscriber = StagingTable::Instrumentation.subscribe(:drop_table) do |event|
        events << event
      end

      session = StagingTable::Session.new(TestUser)
      session.create_table
      session.drop_table

      expect(events.size).to eq(1)
      event = events.first
      expect(event.payload[:source_model]).to eq(TestUser)

      StagingTable::Instrumentation.unsubscribe(subscriber)
    end
  end

  describe "staging_table.insert event" do
    it "instruments record insertion" do
      events = []
      subscriber = StagingTable::Instrumentation.subscribe(:insert) do |event|
        events << event
      end

      StagingTable.stage(TestUser) do |staging|
        staging.insert([
          {name: "John", email: "john@example.com"},
          {name: "Jane", email: "jane@example.com"}
        ])
      end

      expect(events.size).to eq(1)
      event = events.first
      expect(event.payload[:source_model]).to eq(TestUser)
      expect(event.payload[:record_count]).to eq(2)
      expect(event.payload[:batch_size]).to eq(1000)

      StagingTable::Instrumentation.unsubscribe(subscriber)
    end
  end

  describe "staging_table.transfer event" do
    it "instruments data transfer" do
      events = []
      subscriber = StagingTable::Instrumentation.subscribe(:transfer) do |event|
        events << event
      end

      StagingTable.stage(TestUser) do |staging|
        staging.insert([{name: "John", email: "john@example.com"}])
      end

      expect(events.size).to eq(1)
      event = events.first
      expect(event.payload[:source_model]).to eq(TestUser)
      expect(event.payload[:strategy]).to eq(:insert)
      expect(event.payload[:staged_count]).to eq(1)
      expect(event.payload[:result]).to be_a(StagingTable::TransferResult)
      expect(event.payload[:result].inserted).to eq(1)

      StagingTable::Instrumentation.unsubscribe(subscriber)
    end
  end

  describe "monitoring all events" do
    it "can track the full lifecycle" do
      events = []
      subscriber = StagingTable::Instrumentation.subscribe_all do |event|
        events << event
      end

      StagingTable.stage(TestUser) do |staging|
        staging.insert([{name: "John", email: "john@example.com"}])
      end

      event_names = events.map(&:name)
      expect(event_names).to include("staging_table.stage")
      expect(event_names).to include("staging_table.create_table")
      expect(event_names).to include("staging_table.insert")
      expect(event_names).to include("staging_table.transfer")
      expect(event_names).to include("staging_table.drop_table")

      StagingTable::Instrumentation.unsubscribe(subscriber)
    end
  end
end
