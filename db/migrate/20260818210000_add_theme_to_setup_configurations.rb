class AddThemeToSetupConfigurations < ActiveRecord::Migration[8.0]
  def change
    add_column :setup_configurations, :theme, :string, null: false, default: "dark"
  end
end
