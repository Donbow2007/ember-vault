class CreatePassages < ActiveRecord::Migration[8.0]
  def up
    create_table :passages do |t|
      t.references :document, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :heading
      t.text :body

      t.timestamps
    end


    add_index :passages, [ :document_id, :position ], unique: true

    create_virtual_table :passages_fts, :fts5,
      [ "heading", "body", "content='passages'", "content_rowid='id'", "tokenize='porter unicode61 remove_diacritics 2'" ]
    execute <<~SQL
      CREATE TRIGGER passages_ai AFTER INSERT ON passages BEGIN
        INSERT INTO passages_fts(rowid, heading, body) VALUES (new.id, new.heading, new.body);
      END;
      CREATE TRIGGER passages_ad AFTER DELETE ON passages BEGIN
        INSERT INTO passages_fts(passages_fts, rowid, heading, body) VALUES('delete', old.id, old.heading, old.body);
      END;
      CREATE TRIGGER passages_au AFTER UPDATE ON passages BEGIN
        INSERT INTO passages_fts(passages_fts, rowid, heading, body) VALUES('delete', old.id, old.heading, old.body);
        INSERT INTO passages_fts(rowid, heading, body) VALUES (new.id, new.heading, new.body);
      END;
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS passages_au"
    execute "DROP TRIGGER IF EXISTS passages_ad"
    execute "DROP TRIGGER IF EXISTS passages_ai"
    drop_virtual_table :passages_fts
    drop_table :passages
  end
end
