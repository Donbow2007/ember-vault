class AddDownloadStateToMapPacks < ActiveRecord::Migration[8.0]
  def change
    add_column :map_packs, :catalog_id, :string
    add_column :map_packs, :catalog_version, :string
    add_column :map_packs, :source_url, :string
    add_column :map_packs, :expected_bytes, :integer, default: 0, null: false
    add_column :map_packs, :downloaded_bytes, :integer, default: 0, null: false
    add_column :map_packs, :status, :string, default: "complete", null: false
    add_column :map_packs, :error_message, :text
    add_index :map_packs, :catalog_id, unique: true
    add_index :map_packs, :status
  end
end
