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

ActiveRecord::Schema[8.0].define(version: 2026_09_30_220000) do
  create_table "assistant_responses", force: :cascade do |t|
    t.text "question", null: false
    t.text "answer"
    t.string "status", default: "queued", null: false
    t.string "response_mode"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_assistant_responses_on_created_at"
    t.index ["status"], name: "index_assistant_responses_on_status"
  end


  create_table "map_packs", force: :cascade do |t|
    t.string "title", null: false
    t.string "stored_path", null: false
    t.integer "byte_size", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "map_features", force: :cascade do |t|
    t.integer "map_pack_id", null: false
    t.string "name"
    t.string "category"
    t.string "kind"
    t.float "latitude"
    t.float "longitude"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["map_pack_id"], name: "index_map_features_on_map_pack_id"
  end



  add_foreign_key "map_features", "map_packs"
end
