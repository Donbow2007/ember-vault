class CreateMapFeatures < ActiveRecord::Migration[8.0]
  def change
    create_table :map_features do |t|
      t.references :content_download, null: false, foreign_key: true
      t.string :name
      t.string :category
      t.string :kind
      t.float :latitude
      t.float :longitude

      t.timestamps
    end
    add_index :map_features, [ :content_download_id, :name ]
    add_index :map_features, [ :content_download_id, :category ]
  end
end
