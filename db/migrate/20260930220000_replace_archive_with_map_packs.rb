class ReplaceArchiveWithMapPacks < ActiveRecord::Migration[8.0]
  def change
    create_table :map_packs do |t|
      t.string :title, null: false
      t.string :stored_path, null: false
      t.integer :byte_size, default: 0, null: false
      t.string :format, default: "pmtiles", null: false
      t.string :region
      t.string :version
      t.timestamps
    end unless table_exists?(:map_packs)

    unless table_exists?(:map_features)
      create_table :map_features do |t|
        t.references :map_pack, null: false, foreign_key: true
        t.string :name
        t.string :category
        t.string :kind
        t.float :latitude
        t.float :longitude
        t.timestamps
      end
      add_index :map_features, [ :map_pack_id, :name ]
      add_index :map_features, [ :map_pack_id, :category ]
    else
      remove_foreign_key :map_features, :content_downloads if foreign_key_exists?(:map_features, :content_downloads)
      remove_column :map_features, :content_download_id if column_exists?(:map_features, :content_download_id)
      add_reference :map_features, :map_pack, null: true, foreign_key: true unless column_exists?(:map_features, :map_pack_id)
    end

    drop_table :passages_fts if table_exists?(:passages_fts)
    drop_table :passages if table_exists?(:passages)
    drop_table :documents if table_exists?(:documents)
    drop_table :content_downloads if table_exists?(:content_downloads)
    drop_table :setup_configurations if table_exists?(:setup_configurations)
    remove_column :assistant_responses, :source_passage_ids if column_exists?(:assistant_responses, :source_passage_ids)
  end
end
