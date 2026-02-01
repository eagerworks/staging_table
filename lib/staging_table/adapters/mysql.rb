module StagingTable
  module Adapters
    class Mysql < Base
      def create_table(temp_table_name, source_table_name, options = {})
        # MySQL's LIKE copies structure and indexes by default
        quoted_temp = connection.quote_table_name(temp_table_name)
        quoted_source = connection.quote_table_name(source_table_name)
        connection.execute("CREATE TABLE #{quoted_temp} LIKE #{quoted_source}")
      end
    end
  end
end
