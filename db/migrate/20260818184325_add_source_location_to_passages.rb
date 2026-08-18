class AddSourceLocationToPassages < ActiveRecord::Migration[8.0]
  def change
    add_column :passages, :source_entry_index, :integer
    add_column :passages, :source_path, :string
    add_column :passages, :source_mime, :string
    add_column :passages, :source_page, :integer
  end
end
