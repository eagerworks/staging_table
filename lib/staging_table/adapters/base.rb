module StagingTable
  module Adapters
    class Base
      attr_reader :connection

      def initialize(connection)
        @connection = connection
      end

      def create_table(temp_table_name, source_table_name, options = {})
        raise NotImplementedError
      end

      def drop_table(temp_table_name)
        quoted_table = connection.quote_table_name(temp_table_name)
        connection.execute("DROP TABLE IF EXISTS #{quoted_table}")
      end

      def self.for(connection)
        adapter_name = connection.adapter_name.downcase
        case adapter_name
        when /postgresql/
          Postgresql.new(connection)
        when /mysql/
          Mysql.new(connection)
        else
          raise Error, "Unsupported adapter: #{adapter_name}"
        end
      end
    end
  end
end
