class AddDeletionProgressToDocumentsAndContentDownloads < ActiveRecord::Migration[8.0]
  def change
    change_table :documents, bulk: true do |t|
      t.integer :deletion_total, default: 0, null: false
      t.integer :deletion_remaining, default: 0, null: false
    end

    change_table :content_downloads, bulk: true do |t|
      t.integer :deletion_total, default: 0, null: false
      t.integer :deletion_remaining, default: 0, null: false
    end
  end
end
