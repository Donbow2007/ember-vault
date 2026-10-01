class CreateAssistantResponses < ActiveRecord::Migration[8.0]
  def change
    create_table :assistant_responses do |t|
      t.text :question, null: false
      t.text :answer
      t.text :source_passage_ids
      t.string :status, null: false, default: "queued"
      t.string :response_mode
      t.text :error_message

      t.timestamps
    end

    add_index :assistant_responses, :status
    add_index :assistant_responses, :created_at
  end
end
