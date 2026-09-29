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

ActiveRecord::Schema[8.1].define(version: 2026_09_29_000001) do
  create_table "citations", force: :cascade do |t|
    t.integer "document_id", null: false
    t.integer "block_index", null: false
    t.integer "start_offset", null: false
    t.integer "end_offset", null: false
    t.string "osis", null: false
    t.integer "start_verse", null: false
    t.integer "end_verse", null: false
    t.index ["document_id"], name: "index_citations_on_document_id"
    t.index ["start_verse", "end_verse"], name: "index_citations_on_start_verse_and_end_verse"
  end

  create_table "correction_events", force: :cascade do |t|
    t.integer "document_id", null: false
    t.string "kind", null: false
    t.text "text", null: false
    t.json "replaced"
    t.string "ui_event"
    t.boolean "from_history", default: false, null: false
    t.string "user_name", null: false
    t.datetime "created_at", null: false
    t.index ["document_id"], name: "index_correction_events_on_document_id"
  end

  create_table "documents", force: :cascade do |t|
    t.string "title", null: false
    t.json "body", null: false
    t.integer "schema_version", default: 1, null: false
    t.text "plain_text", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "ocr_runs", force: :cascade do |t|
    t.string "key", null: false
    t.string "engine", null: false
    t.string "engine_version"
    t.integer "page"
    t.text "text", null: false
    t.json "glyphs", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_ocr_runs_on_key", unique: true
  end

  create_table "provenance_spans", force: :cascade do |t|
    t.integer "document_id", null: false
    t.integer "block_index", null: false
    t.integer "start_offset", null: false
    t.integer "end_offset", null: false
    t.string "origin", null: false
    t.string "run_key"
    t.string "by"
    t.string "session"
    t.index ["document_id", "block_index", "start_offset"], name: "idx_on_document_id_block_index_start_offset_1acf8177c5"
    t.index ["document_id"], name: "index_provenance_spans_on_document_id"
    t.index ["origin"], name: "index_provenance_spans_on_origin"
    t.index ["run_key"], name: "index_provenance_spans_on_run_key"
  end

  add_foreign_key "citations", "documents"
  add_foreign_key "correction_events", "documents"
  add_foreign_key "provenance_spans", "documents"
end
