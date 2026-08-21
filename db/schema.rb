# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_08_21_140000) do
  create_table "assistant_responses", force: :cascade do |t|
    t.text "question", null: false
    t.text "answer"
    t.text "source_passage_ids"
    t.string "status", default: "queued", null: false
    t.string "response_mode"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_assistant_responses_on_created_at"
    t.index ["status"], name: "index_assistant_responses_on_status"
  end

  create_table "content_downloads", force: :cascade do |t|
    t.string "resource_id"
    t.string "title"
    t.string "source_url"
    t.string "kind"
    t.integer "expected_bytes"
    t.integer "downloaded_bytes"
    t.string "status"
    t.string "destination_path"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "deletion_total", default: 0, null: false
    t.integer "deletion_remaining", default: 0, null: false
    t.integer "package_version"
    t.string "content_hash"
    t.string "package_id"
    t.index ["package_id"], name: "index_content_downloads_on_package_id", unique: true, where: "package_id IS NOT NULL"
  end

  create_table "documents", force: :cascade do |t|
    t.string "title", null: false
    t.string "original_filename", null: false
    t.string "content_type", null: false
    t.string "stored_path", null: false
    t.string "status", default: "queued", null: false
    t.integer "byte_size", default: 0, null: false
    t.integer "passage_count", default: 0, null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "content_download_id"
    t.integer "deletion_total", default: 0, null: false
    t.integer "deletion_remaining", default: 0, null: false
    t.index ["content_download_id"], name: "index_documents_on_content_download_id"
    t.index ["created_at"], name: "index_documents_on_created_at"
    t.index ["status"], name: "index_documents_on_status"
  end

  create_table "map_features", force: :cascade do |t|
    t.integer "content_download_id", null: false
    t.string "name"
    t.string "category"
    t.string "kind"
    t.float "latitude"
    t.float "longitude"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["content_download_id"], name: "index_map_features_on_content_download_id"
  end

  create_table "passages", force: :cascade do |t|
    t.integer "document_id", null: false
    t.integer "position", null: false
    t.string "heading"
    t.text "body"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "source_entry_index"
    t.string "source_path"
    t.string "source_mime"
    t.integer "source_page"
    t.index ["document_id", "position"], name: "index_passages_on_document_id_and_position", unique: true
    t.index ["document_id"], name: "index_passages_on_document_id"
  end

  create_table "setup_configurations", force: :cascade do |t|
    t.text "capabilities"
    t.text "selected_resources"
    t.integer "projected_size_mb"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "ai_profile", default: "disabled", null: false
    t.string "theme", default: "dark", null: false
  end

  create_table "terms_acceptances", force: :cascade do |t|
    t.string "terms_version", null: false
    t.datetime "accepted_at", null: false
    t.string "application_version", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["terms_version"], name: "index_terms_acceptances_on_terms_version", unique: true
  end

  add_foreign_key "documents", "content_downloads"
  add_foreign_key "map_features", "content_downloads"
  add_foreign_key "passages", "documents"

  # Virtual tables defined in this database.
  # Note that virtual tables may not work with other database engines. Be careful if changing database.
  create_virtual_table "passages_fts", "fts5", ["heading", "body", "content='passages'", "content_rowid='id'", "tokenize='porter unicode61 remove_diacritics 2'"]
end
