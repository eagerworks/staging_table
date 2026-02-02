# frozen_string_literal: true

module StagingTable
  class ModelFactory
    def self.build(source_model, table_name, excluded_columns: [])
      Class.new(source_model) do
        self.table_name = table_name
        self.ignored_columns = excluded_columns

        # Ensure we don't inherit STI behavior unless intended for the temp table
        self.inheritance_column = nil unless source_model.inheritance_column == "type" && source_model.columns_hash["type"]

        def self.model_name
          ActiveModel::Name.new(self, nil, superclass.name)
        end

        # Prevent the dynamic class from being added to the global constant namespace
        def self.name
          "#{superclass.name}::Staging_#{table_name}"
        end
      end
    end
  end
end
