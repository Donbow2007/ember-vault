class AddContentDownloadToDocuments < ActiveRecord::Migration[8.0]
  def change
    add_reference :documents, :content_download, null: true, foreign_key: true
  end
end
