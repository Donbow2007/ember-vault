class CreateSetupConfigurations < ActiveRecord::Migration[8.0]
  def change
    create_table :setup_configurations do |t|
      t.text :capabilities, null: false
      t.text :selected_resources, null: false
      t.integer :projected_size_mb, null: false, default: 0
      t.datetime :completed_at

      t.timestamps
    end

    add_index :setup_configurations, :completed_at
  end
end
