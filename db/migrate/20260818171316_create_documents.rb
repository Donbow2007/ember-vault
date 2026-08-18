class CreateDocuments < ActiveRecord::Migration[8.0]
  def change
    create_table :documents do |t|
      t.string :title, null: false
      t.string :original_filename, null: false
      t.string :content_type, null: false
      t.string :stored_path, null: false
      t.string :status, null: false, default: "queued"
      t.integer :byte_size, null: false, default: 0
      t.integer :passage_count, null: false, default: 0
      t.text :error_message

      t.timestamps
    end

    add_index :documents, :status
    add_index :documents, :created_at
  end
end
