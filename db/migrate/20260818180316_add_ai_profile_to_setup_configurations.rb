class AddAiProfileToSetupConfigurations < ActiveRecord::Migration[8.0]
  def change
    add_column :setup_configurations, :ai_profile, :string, null: false, default: "disabled"
  end
end
