class AddInstalledKnowledgeState < ActiveRecord::Migration[8.0]
  def change
    add_column :content_downloads, :installed_package_version, :integer
    add_column :content_downloads, :installed_content_hash, :string
    add_column :documents, :external_id, :string
    add_column :documents, :content_hash, :string
    add_index :documents, [ :content_download_id, :external_id ], unique: true,
      where: "external_id IS NOT NULL", name: "index_documents_on_download_and_external_id"
  end
end
