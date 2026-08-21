class CreateTermsAcceptances < ActiveRecord::Migration[8.0]
  def change
    create_table :terms_acceptances do |t|
      t.string :terms_version, null: false
      t.datetime :accepted_at, null: false
      t.string :application_version, null: false

      t.timestamps
    end

    add_index :terms_acceptances, :terms_version, unique: true
  end
end
