# frozen_string_literal: true

module StagingTable
  class ConflictResolver
    VALID_STRATEGIES = %i[greatest least new existing sum coalesce].freeze

    attr_reader :connection, :options

    def initialize(connection, options)
      @connection = connection
      @options = options || {}
      validate_options! if enabled?
    end

    def enabled?
      options.is_a?(Hash) && options[:target].present? && options[:update].present?
    end

    def conflict_clause(table_name)
      return "" unless enabled?

      target_columns = Array(options[:target])
      update_rules = options[:update]

      quoted_targets = target_columns.map { |c| connection.quote_column_name(c) }
      set_clauses = build_set_clauses(table_name, update_rules)

      case adapter
      when :postgresql, :sqlite
        on_conflict_clause(quoted_targets, set_clauses)
      when :mysql
        mysql_conflict_clause(quoted_targets, set_clauses)
      else
        raise AdapterError, "Conflict resolution is not supported for adapter: #{connection.adapter_name}"
      end
    end

    private

    def adapter
      name = connection.adapter_name.downcase
      case name
      when /postgresql/ then :postgresql
      when /mysql|trilogy/ then :mysql
      when /sqlite/ then :sqlite
      end
    end

    def validate_options!
      unless options[:target].is_a?(Array) || options[:target].is_a?(Symbol)
        raise ConfigurationError, "insert_on_conflict :target must be a symbol or array of symbols"
      end

      unless options[:update].is_a?(Hash)
        raise ConfigurationError, "insert_on_conflict :update must be a hash"
      end

      options[:update].each do |_column, strategy|
        next if strategy.is_a?(String) # Raw SQL is allowed
        unless VALID_STRATEGIES.include?(strategy)
          raise ConfigurationError, "Invalid conflict resolution strategy: #{strategy}. Valid strategies are: #{VALID_STRATEGIES.join(", ")}, or a raw SQL string."
        end
      end
    end

    def build_set_clauses(table_name, update_rules)
      quoted_table = connection.quote_table_name(table_name)

      update_rules.filter_map do |column, strategy|
        next if strategy == :existing # :existing means keep current value (omit from SET)

        quoted_col = connection.quote_column_name(column)
        value = resolve_value(quoted_table, quoted_col, strategy)
        "#{quoted_col} = #{value}"
      end
    end

    def resolve_value(table_name, quoted_col, strategy)
      case strategy
      when :greatest
        greatest_expression(table_name, quoted_col)
      when :least
        least_expression(table_name, quoted_col)
      when :new
        new_value_expression(quoted_col)
      when :sum
        sum_expression(table_name, quoted_col)
      when :coalesce
        coalesce_expression(table_name, quoted_col)
      when String
        strategy # Raw SQL passed through
      else
        raise ConfigurationError, "Unknown conflict resolution strategy: #{strategy}"
      end
    end

    def greatest_expression(table_name, quoted_col)
      case adapter
      when :postgresql
        "GREATEST(#{table_name}.#{quoted_col}, EXCLUDED.#{quoted_col})"
      when :mysql
        "GREATEST(#{table_name}.#{quoted_col}, VALUES(#{quoted_col}))"
      when :sqlite
        "MAX(#{table_name}.#{quoted_col}, excluded.#{quoted_col})"
      end
    end

    def least_expression(table_name, quoted_col)
      case adapter
      when :postgresql
        "LEAST(#{table_name}.#{quoted_col}, EXCLUDED.#{quoted_col})"
      when :mysql
        "LEAST(#{table_name}.#{quoted_col}, VALUES(#{quoted_col}))"
      when :sqlite
        "MIN(#{table_name}.#{quoted_col}, excluded.#{quoted_col})"
      end
    end

    def new_value_expression(quoted_col)
      case adapter
      when :postgresql
        "EXCLUDED.#{quoted_col}"
      when :mysql
        "VALUES(#{quoted_col})"
      when :sqlite
        "excluded.#{quoted_col}"
      end
    end

    def sum_expression(table_name, quoted_col)
      case adapter
      when :postgresql
        "#{table_name}.#{quoted_col} + EXCLUDED.#{quoted_col}"
      when :mysql
        "#{table_name}.#{quoted_col} + VALUES(#{quoted_col})"
      when :sqlite
        "#{table_name}.#{quoted_col} + excluded.#{quoted_col}"
      end
    end

    def coalesce_expression(table_name, quoted_col)
      case adapter
      when :postgresql
        "COALESCE(EXCLUDED.#{quoted_col}, #{table_name}.#{quoted_col})"
      when :mysql
        "COALESCE(VALUES(#{quoted_col}), #{table_name}.#{quoted_col})"
      when :sqlite
        "COALESCE(excluded.#{quoted_col}, #{table_name}.#{quoted_col})"
      end
    end

    def on_conflict_clause(quoted_targets, set_clauses)
      return " ON CONFLICT (#{quoted_targets.join(", ")}) DO NOTHING" if set_clauses.empty?

      " ON CONFLICT (#{quoted_targets.join(", ")}) DO UPDATE SET #{set_clauses.join(", ")}"
    end

    def mysql_conflict_clause(quoted_targets, set_clauses)
      # MySQL has no DO NOTHING; emit a no-op assignment on a target column so
      # the duplicate row is silently ignored instead of raising.
      if set_clauses.empty?
        noop_col = quoted_targets.first
        return " ON DUPLICATE KEY UPDATE #{noop_col} = #{noop_col}"
      end

      " ON DUPLICATE KEY UPDATE #{set_clauses.join(", ")}"
    end
  end
end
