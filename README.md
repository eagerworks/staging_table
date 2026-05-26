# 🎭 StagingTable

**The red carpet for your data before it hits the main stage.**

[![Gem Version](https://badge.fury.io/rb/staging_table.svg)](https://badge.fury.io/rb/staging_table)
[![Test Status](https://github.com/eagerworks/staging_table/actions/workflows/test.yml/badge.svg)](https://github.com/eagerworks/staging_table/actions)
[![RBS](https://github.com/eagerworks/staging_table/actions/workflows/rbs.yml/badge.svg)](https://github.com/eagerworks/staging_table/actions/workflows/rbs.yml)

Stop shoving data directly into your production tables like a savage. Give it a dressing room first! 

`StagingTable` lets you bulk import data into a temporary "staging" table, validate/massage it, and *then* gracefully transfer it to your real tables using efficient SQL strategies.

It's like `INSERT INTO ... SELECT` but with a Ruby DSL that makes you smile.

## 🌟 Why?

Importing large datasets is hard.
- **Direct inserts** are slow and bypass validations.
- **ActiveRecord** is safe but slow for millions of records.
- **Raw SQL** is fast but messy and hard to maintain.

**StagingTable** gives you the best of both worlds:
1.  **🚀 Speed**: Bulk insert into a temp table (no index overhead yet).
2.  **🛡️ Safety**: Validate or query the data *before* it touches your real table.
3.  **🧹 Cleanliness**: Automatic cleanup of temp tables.
4.  **🔄 Power**: Built-in support for `UPSERT` (INSERT ON CONFLICT) and duplicate handling.

---

## 📦 Installation

Add this line to your application's Gemfile:

```ruby
gem 'staging_table'
```

And then execute:

```bash
bundle install
```

---

## 🛠️ Usage

### The "Happy Path" (Block Syntax)

The simplest way to use StagingTable. It handles the creation and cleanup of the temporary table automatically.

```ruby
# 1. Create a staging table that mirrors the 'users' table
StagingTable.stage(User) do |staging|
  
  # 2. Bulk insert data (Hashes, AR Objects, or Relations)
  staging.insert([
    { name: 'John Doe', email: 'john@example.com' },
    { name: 'Jane Doe', email: 'jane@example.com' }
  ])
  
  # 3. The 'staging' object is a real ActiveRecord model!
  #    You can query it, validate it, or massage data.
  puts "Staged count: #{staging.count}"
  staging.where(email: nil).delete_all
  
  # 4. When the block exits, data is automatically transferred 
  #    to the 'users' table using a single SQL statement.
end
```

### 📥 Importing Data

The `insert` method is flexible. Feed it whatever you have:

```ruby
StagingTable.stage(User) do |staging|
  # 🍎 Array of Hashes
  staging.insert([
    { name: 'John', email: 'john@example.com' },
    { name: 'Jane', email: 'jane@example.com' }
  ])

  # 🍊 Array of ActiveRecord objects
  staging.insert(User.where(active: true).to_a)

  # 🍇 ActiveRecord::Relation (Lazy loading)
  staging.insert(User.where(role: 'admin'))
end
```

For massive datasets, use `insert_from_query` to process in batches and keep memory usage low:

```ruby
StagingTable.stage(User) do |staging|
  # Processes in batches of 1000 (configurable)
  staging.insert_from_query(User.where(needs_migration: true))
end
```

### ⚔️ Handling Duplicates (Upsert)

Don't let duplicates crash your party. Configure the transfer strategy to handle conflicts gracefully.

```ruby
StagingTable.stage(User,
  transfer_strategy: :upsert,    # Default is :insert
  conflict_target: [:email],     # Column(s) to check for conflicts
  conflict_action: :update       # :update (overwrite) or :ignore (skip)
) do |staging|
  staging.insert(records)
end
```

### 📦 Extra Columns

Need columns in your staging table that don't exist in the source model? Perfect for tracking import metadata, priorities, or processing flags.

```ruby
StagingTable.stage(User,
  extra_columns: {
    priority: :integer,                              # Simple type
    processed: {type: :boolean, default: false},    # With options
    import_batch: {type: :string, default: "batch_1"}
  }
) do |staging|
  # Insert with extra column values
  staging.insert([
    {name: "John", email: "john@example.com", priority: 1},
    {name: "Jane", email: "jane@example.com", priority: 2}
  ])

  # Query using extra columns
  staging.where(priority: 1).find_each do |record|
    # Process high priority records first
  end

  # Mark as processed
  staging.where(processed: false).update_all(processed: true)

  # Extra columns are automatically excluded during transfer
end
```

**Supported column types:** `:string`, `:text`, `:integer`, `:bigint`, `:float`, `:decimal`, `:boolean`, `:datetime`, `:date`, `:time`, `:binary`, `:json`, `:jsonb` (PostgreSQL), `:uuid` (PostgreSQL)

### 🔀 Staging Insert Conflict Resolution

Handle conflicts when inserting into the staging table itself. Useful when you're aggregating data from multiple sources or processing the same records multiple times.

```ruby
StagingTable.stage(User,
  extra_columns: {priority: :integer, score: :integer},
  insert_on_conflict: {
    target: [:email],           # Column(s) to detect conflicts
    update: {
      priority: :greatest,      # Keep the higher value
      score: :sum,              # Add values together
      name: :new,               # Use the incoming value
      age: :existing            # Keep the existing value (skip update)
    }
  }
) do |staging|
  # First batch
  staging.insert([
    {email: "john@example.com", name: "John", priority: 1, score: 10}
  ])

  # Second batch - conflicts are resolved automatically
  staging.insert([
    {email: "john@example.com", name: "Johnny", priority: 5, score: 20}
  ])

  # Result: priority=5 (greatest), score=30 (sum), name="Johnny" (new)
end
```

**Available resolution strategies:**

| Strategy | Description | Example Result |
|----------|-------------|----------------|
| `:greatest` | Keep the larger value | `GREATEST(existing, incoming)` |
| `:least` | Keep the smaller value | `LEAST(existing, incoming)` |
| `:new` | Use the incoming value | Overwrites existing |
| `:existing` | Keep the existing value | Skips update for this column |
| `:sum` | Add values together | `existing + incoming` |
| `:coalesce` | Use incoming if not null, else existing | `COALESCE(incoming, existing)` |
| `"raw SQL"` | Custom SQL expression | `"COALESCE(excluded.col, staging.col)"` |

**Note:** For PostgreSQL and SQLite, `target` columns are used explicitly in the `ON CONFLICT` clause and must be covered by a unique or exclusion constraint.

For MySQL, `ON DUPLICATE KEY UPDATE` is triggered by *any* violated unique (or primary) key on the table — not just the ones listed in `:target`. If your staging table has multiple unique indexes, the update may fire on conflicts you did not intend. Make sure the column(s) you list in `:target` are the only unique constraint that matters for your use case, or remove any other unique indexes before inserting. Raw SQL strategies using `VALUES(col)` are deprecated since MySQL 8.0.20; the clause still works but may emit warnings.

### 📊 Transfer Results

Every transfer returns a `TransferResult` with detailed statistics:

```ruby
result = StagingTable.stage(User) do |staging|
  staging.insert(records)
end

puts result.inserted  # => 450  (new records)
puts result.updated   # => 50   (updated via upsert)
puts result.skipped   # => 10   (ignored conflicts)
puts result.total     # => 510  (total processed)
puts result.success?  # => true (any inserts or updates?)

# Also available as a hash
result.to_h # => { inserted: 450, updated: 50, skipped: 10, total: 510 }
```

### 🪝 Callbacks

Hook into the staging lifecycle to validate, transform, or log:

```ruby
StagingTable.stage(User,
  before_insert: ->(session) {
    Rails.logger.info "Starting import..."
  },
  after_insert: ->(session, records) {
    Rails.logger.info "Staged #{records.count} records"
  },
  before_transfer: ->(session) {
    # Clean up invalid data before transfer
    session.where(email: nil).delete_all
    session.where(status: 'banned').delete_all
  },
  after_transfer: ->(session, result) {
    Rails.logger.info "Imported #{result.inserted} new, updated #{result.updated}"
  }
) do |staging|
  staging.insert(records)
end
```

### 📡 Instrumentation (ActiveSupport::Notifications)

Monitor and debug your imports in production with built-in instrumentation:

```ruby
# Subscribe to transfer events
StagingTable::Instrumentation.subscribe(:transfer) do |event|
  Rails.logger.info "[StagingTable] Transfer to #{event.payload[:source_table]} " \
                    "completed in #{event.duration.round(2)}ms"
  StatsD.measure('staging_table.transfer.duration', event.duration)
  StatsD.increment('staging_table.transfer.inserted', event.payload[:result].inserted)
end

# Subscribe to all StagingTable events
StagingTable::Instrumentation.subscribe_all do |event|
  Rails.logger.debug "[StagingTable] #{event.name}: #{event.duration.round(2)}ms"
end
```

**Available Events:**

| Event | Payload | Description |
|-------|---------|-------------|
| `staging_table.stage` | `source_model`, `source_table`, `options`, `result` | Wraps the entire staging block |
| `staging_table.create_table` | `source_model`, `source_table`, `staging_table` | When staging table is created |
| `staging_table.insert` | `source_model`, `source_table`, `staging_table`, `record_count`, `batch_size` | When records are inserted |
| `staging_table.transfer` | `source_model`, `source_table`, `staging_table`, `strategy`, `staged_count`, `result` | When data is transferred |
| `staging_table.drop_table` | `source_model`, `source_table`, `staging_table` | When staging table is dropped |

You can also use standard ActiveSupport::Notifications directly:

```ruby
ActiveSupport::Notifications.subscribe('staging_table.transfer') do |event|
  # Your monitoring code here
end
```

### 🎛️ Manual Control

Need to keep the staging table alive across multiple background jobs? We got you.

**Note:** Temporary tables in PostgreSQL are session-specific. This only works if you stay in the same DB connection!

```ruby
# Create the session
session = StagingTable::Session.new(User, excluded_columns: %w[created_at updated_at])
session.create_table

begin
  # Insert data in chunks
  session.insert(batch_1)
  session.insert(batch_2)
  
  # Run some sanity checks
  if session.where(status: 'banned').exists?
    raise "Whoa there! No banned users allowed."
  end
  
  # Commit to the real table
  result = session.transfer
  puts "Transferred #{result.total} records"
ensure
  # Always clean up your mess
  session.drop_table
end
```

---

## ⚙️ Configuration

Set global defaults in an initializer (e.g., `config/initializers/staging_table.rb`):

```ruby
StagingTable.configure do |config|
  config.default_batch_size = 2000
  config.default_transfer_strategy = :insert # or :upsert
end
```

---

## 🔍 Type Checking (RBS)

This gem ships with [RBS](https://github.com/ruby/rbs) type signatures for static type checking. The signatures are located in the `sig/` directory and are validated in CI.

### Using the Type Signatures

If you want to type-check your own code that uses StagingTable:

```bash
# Install RBS and the collection for dependencies
gem install rbs
rbs collection install

# Validate signatures
rbs -I sig validate
```

### Using with Steep

For full type checking with [Steep](https://github.com/soutaro/steep):

```ruby
# Gemfile
gem 'steep', group: :development
```

```ruby
# Steepfile
target :lib do
  signature "sig"
  check "lib"
  library "activerecord"
  library "activesupport"
end
```

```bash
bundle exec steep check
```

---

## 💾 Supported Databases

We speak your language.

| Database | Strategy |
|----------|----------|
| **PostgreSQL** | `CREATE TABLE ... (LIKE ... INCLUDING DEFAULTS)` + `INSERT ... ON CONFLICT` |
| **MySQL** | `CREATE TABLE ... LIKE ...` + `INSERT ... ON DUPLICATE KEY UPDATE` |
| **SQLite** | Copies structure from `sqlite_master` + `INSERT ... ON CONFLICT` |

---

## 🤝 Contributing

Found a bug? Want to add support for Oracle? (Please don't, but if you must...)

1.  Fork it
2.  Create your feature branch (`git checkout -b my-new-feature`)
3.  Commit your changes (`git commit -am 'Add some feature'`)
4.  Push to the branch (`git push origin my-new-feature`)
5.  Create new Pull Request

### Running Tests

We support the big three. Set up your environment variables for PG/MySQL or just run SQLite tests out of the box.

```bash
# Run everything
bundle exec rake spec

# Pick your poison
bundle exec rake spec:postgresql
bundle exec rake spec:mysql
bundle exec rspec --tag sqlite
```

---

## 🙏 Special Thanks

Special thanks to [agustin-peluffo](https://github.com/agustin-peluffo) who created the first implementation for a project!

---

*Made with ❤️ by [eagerworks](https://eagerworks.com)*
