# StagingTable

Handles mass data imports via temporary staging tables, supporting PostgreSQL and MySQL. This gem provides a clean DSL for creating temporary tables that mirror your source model, performing bulk inserts into them, and then transferring the data to the destination table using efficient SQL strategies.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'staging_table'
```

## Usage

### Basic Usage

The simplest way to use StagingTable is with the block syntax. This handles the creation and cleanup of the temporary table automatically.

```ruby
StagingTable.stage(User) do |staging|
  # staging.model is a dynamic ActiveRecord class pointing to the temp table
  
  # Bulk insert raw hashes
  staging.insert([
    { name: 'John Doe', email: 'john@example.com' },
    { name: 'Jane Doe', email: 'jane@example.com' }
  ])
  
  # You can also query the staging table using ActiveRecord methods
  puts "Staged count: #{staging.count}"
  
  # Data is automatically transferred to the 'users' table when the block exits
end
```

### Inserting Data

The `insert` method accepts multiple input types:

```ruby
StagingTable.stage(User) do |staging|
  # Array of hashes
  staging.insert([
    { name: 'John', email: 'john@example.com' },
    { name: 'Jane', email: 'jane@example.com' }
  ])

  # Array of ActiveRecord objects
  staging.insert(User.where(active: true).to_a)

  # ActiveRecord::Relation (query)
  staging.insert(User.where(role: 'admin'))
end
```

For very large datasets, use `insert_from_query` which processes records in batches to avoid memory issues:

```ruby
StagingTable.stage(User) do |staging|
  # Processes in batches (default: 1000 records per batch)
  staging.insert_from_query(User.where(needs_migration: true))
end
```

### Upsert Strategy (On Conflict)

You can configure the transfer strategy to handle duplicates.

```ruby
StagingTable.stage(User, 
  transfer_strategy: :upsert,
  conflict_target: [:email],     # Column(s) to check for conflicts
  conflict_action: :update       # :update or :ignore
) do |staging|
  staging.insert(records)
end
```

### Configuration

You can set global defaults in an initializer:

```ruby
StagingTable.configure do |config|
  config.default_batch_size = 2000
  config.default_transfer_strategy = :insert
end
```

### Manual Control

For more complex workflows (e.g., across multiple background jobs), you can manage the session manually. Note that temporary tables in PostgreSQL are session-specific, so this only works within the same database connection.

```ruby
session = StagingTable::Session.new(User, excluded_columns: %w[created_at updated_at])
session.create_table

begin
  session.insert(batch_1)
  session.insert(batch_2)
  
  # Perform custom validation or cleanup on the staging table
  session.where(invalid: true).delete_all
  
  session.transfer
ensure
  session.drop_table
end
```

## Supported Databases

- **PostgreSQL**: Uses `CREATE TABLE ... (LIKE ... INCLUDING DEFAULTS)` and `INSERT ... ON CONFLICT ...`
- **MySQL**: Uses `CREATE TABLE ... LIKE ...` and `INSERT ... ON DUPLICATE KEY UPDATE ...`

## Development

After checking out the repo, run `bundle install` to install dependencies.

### Running Tests

The test suite requires PostgreSQL and/or MySQL databases. Configure the connection via environment variables:

```bash
# PostgreSQL
export POSTGRES_DB=staging_table_test
export POSTGRES_USER=postgres
export POSTGRES_PASSWORD=
export POSTGRES_HOST=localhost

# MySQL
export MYSQL_DB=staging_table_test
export MYSQL_USER=root
export MYSQL_PASSWORD=
export MYSQL_HOST=localhost
```

Run all tests:

```bash
bundle exec rake spec
```

Run only PostgreSQL tests:

```bash
bundle exec rake spec:postgresql
```

Run only MySQL tests:

```bash
bundle exec rake spec:mysql
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/syntaxrails/staging_table.
