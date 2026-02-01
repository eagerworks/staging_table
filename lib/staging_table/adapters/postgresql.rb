module StagingTable
  module Adapters
    class Postgresql < Base
      def create_table(temp_table_name, source_table_name, options = {})
        quoted_temp = connection.quote_table_name(temp_table_name)
        quoted_source = connection.quote_table_name(source_table_name)
        sql = "CREATE TABLE #{quoted_temp} (LIKE #{quoted_source} INCLUDING DEFAULTS"
        sql += " INCLUDING INDEXES" if options[:include_indexes]
        sql += ")"
        connection.execute(sql)
      end
    end
  end
end
