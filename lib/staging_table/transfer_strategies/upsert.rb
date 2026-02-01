module StagingTable
  module TransferStrategies
    class Upsert
      def initialize(source_model, staging_model, options = {})
        @source_model = source_model
        @staging_model = staging_model
        @options = options
        @connection = source_model.connection
      end

      def transfer
        @staged_count = @staging_model.count
        return TransferResult.new if @staged_count.zero?

        adapter_name = @connection.adapter_name.downcase
        case adapter_name
        when /postgresql/
          postgresql_upsert
        when /mysql/
          mysql_upsert
        when /sqlite/
          sqlite_upsert
        else
          raise AdapterError, "Upsert strategy not supported for adapter: #{adapter_name}. Supported adapters are PostgreSQL, MySQL, and SQLite."
        end
      end

      private

      def postgresql_upsert
        conflict_target = Array(@options[:conflict_target])
        if conflict_target.empty?
          raise ConfigurationError, "PostgreSQL upsert requires :conflict_target option specifying the unique constraint columns. Example: transfer_strategy: :upsert, conflict_target: [:email]"
        end

        columns = column_names.map { |c| quote_column(c) }.join(", ")
        conflict_target_sql = conflict_target.map { |c| quote_column(c) }.join(", ")
        source_table = quote_table(@source_model.table_name)
        staging_table = quote_table(@staging_model.table_name)

        if @options[:conflict_action] == :ignore
          # Use RETURNING to count actual inserts (rows where xmax = 0 are new inserts)
          sql = "INSERT INTO #{source_table} (#{columns}) SELECT #{columns} FROM #{staging_table}"
          sql += " ON CONFLICT (#{conflict_target_sql}) DO NOTHING"

          count_before = @source_model.count
          @connection.execute(sql)
          count_after = @source_model.count

          inserted = count_after - count_before
          skipped = @staged_count - inserted
          TransferResult.new(inserted: inserted, skipped: skipped)
        else
          updates = column_names.reject { |c| conflict_target.map(&:to_s).include?(c.to_s) || c == "id" }
            .map { |c| "#{quote_column(c)} = EXCLUDED.#{quote_column(c)}" }.join(", ")

          # Count existing records that match conflict target before upsert
          count_before = @source_model.count
          @connection.execute(
            "INSERT INTO #{source_table} (#{columns}) SELECT #{columns} FROM #{staging_table} " \
            "ON CONFLICT (#{conflict_target_sql}) DO UPDATE SET #{updates}"
          )
          count_after = @source_model.count

          inserted = count_after - count_before
          updated = @staged_count - inserted
          TransferResult.new(inserted: inserted, updated: updated)
        end
      end

      def mysql_upsert
        columns = column_names.map { |c| quote_column(c) }.join(", ")
        source_table = quote_table(@source_model.table_name)
        staging_table = quote_table(@staging_model.table_name)

        count_before = @source_model.count

        if @options[:conflict_action] == :ignore
          sql = "INSERT IGNORE INTO #{source_table} (#{columns}) SELECT #{columns} FROM #{staging_table}"
          @connection.execute(sql)

          count_after = @source_model.count
          inserted = count_after - count_before
          skipped = @staged_count - inserted
          TransferResult.new(inserted: inserted, skipped: skipped)
        else
          sql = "INSERT INTO #{source_table} (#{columns}) SELECT #{columns} FROM #{staging_table}"
          updates = column_names.reject { |c| c == "id" }
            .map { |c| "#{quote_column(c)} = VALUES(#{quote_column(c)})" }.join(", ")
          sql += " ON DUPLICATE KEY UPDATE #{updates}"
          @connection.execute(sql)

          count_after = @source_model.count
          inserted = count_after - count_before
          updated = @staged_count - inserted
          TransferResult.new(inserted: inserted, updated: updated)
        end
      end

      def sqlite_upsert
        conflict_target = Array(@options[:conflict_target])
        if conflict_target.empty?
          raise ConfigurationError, "SQLite upsert requires :conflict_target option specifying the unique constraint columns. Example: transfer_strategy: :upsert, conflict_target: [:email]"
        end

        columns = column_names.map { |c| quote_column(c) }.join(", ")
        source_table = quote_table(@source_model.table_name)
        staging_table = quote_table(@staging_model.table_name)

        count_before = @source_model.count

        if @options[:conflict_action] == :ignore
          sql = "INSERT OR IGNORE INTO #{source_table} (#{columns}) SELECT #{columns} FROM #{staging_table}"
          @connection.execute(sql)

          count_after = @source_model.count
          inserted = count_after - count_before
          skipped = @staged_count - inserted
          TransferResult.new(inserted: inserted, skipped: skipped)
        else
          conflict_target_sql = conflict_target.map { |c| quote_column(c) }.join(", ")
          updates = column_names.reject { |c| conflict_target.map(&:to_s).include?(c.to_s) || c == "id" }
            .map { |c| "#{quote_column(c)} = excluded.#{quote_column(c)}" }.join(", ")

          # Build individual upsert statements for each record
          @staging_model.all.each do |record|
            values_sql = column_names.map { |c| quote(record[c]) }.join(", ")
            upsert_sql = "INSERT INTO #{source_table} (#{columns}) VALUES (#{values_sql}) " \
                         "ON CONFLICT (#{conflict_target_sql}) DO UPDATE SET #{updates}"
            @connection.execute(upsert_sql)
          end

          count_after = @source_model.count
          inserted = count_after - count_before
          updated = @staged_count - inserted
          TransferResult.new(inserted: inserted, updated: updated)
        end
      end

      def quote(value)
        @connection.quote(value)
      end

      def column_names
        @staging_model.column_names
      end

      def quote_column(name)
        @connection.quote_column_name(name)
      end

      def quote_table(name)
        @connection.quote_table_name(name)
      end
    end
  end
end
