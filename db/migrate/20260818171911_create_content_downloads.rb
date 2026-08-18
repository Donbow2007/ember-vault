class CreateContentDownloads < ActiveRecord::Migration[8.0]
  def change
    create_table :content_downloads do |t|
      t.string :resource_id, null: false
      t.string :title, null: false
      t.string :source_url, null: false
      t.string :kind, null: false
      t.integer :expected_bytes, null: false, default: 0
      t.integer :downloaded_bytes, null: false, default: 0
      t.string :status, null: false, default: "queued"
      t.string :destination_path
      t.text :error_message

      t.timestamps
    end

    add_index :content_downloads, :resource_id, unique: true
    add_index :content_downloads, :status
  end
end
