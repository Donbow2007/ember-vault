class AddKnowledgePackageFieldsToContentDownloads < ActiveRecord::Migration[8.0]
  def change
    add_column :content_downloads, :package_version, :integer
    add_column :content_downloads, :content_hash, :string
    add_column :content_downloads, :package_id, :string
    add_index :content_downloads, :package_id, unique: true, where: "package_id IS NOT NULL"
  end
end
