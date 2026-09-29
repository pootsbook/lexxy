class CreateProvenanceSchema < ActiveRecord::Migration[8.1]
  def change
    create_table :documents do |t|
      t.string :title, null: false
      t.json :body, null: false
      t.integer :schema_version, null: false, default: 1
      t.text :plain_text, null: false, default: ""
      t.timestamps
    end

    create_table :ocr_runs do |t|
      t.string :key, null: false, index: { unique: true }
      t.string :engine, null: false
      t.string :engine_version
      t.integer :page
      t.text :text, null: false
      t.json :glyphs, null: false
      t.timestamps
    end

    create_table :citations do |t|
      t.references :document, null: false, foreign_key: true
      t.integer :block_index, null: false
      t.integer :start_offset, null: false
      t.integer :end_offset, null: false
      t.string :osis, null: false
      t.integer :start_verse, null: false
      t.integer :end_verse, null: false
      t.index [ :start_verse, :end_verse ]
    end

    create_table :provenance_spans do |t|
      t.references :document, null: false, foreign_key: true
      t.integer :block_index, null: false
      t.integer :start_offset, null: false
      t.integer :end_offset, null: false
      t.string :origin, null: false
      t.string :run_key
      t.string :by
      t.string :session
      t.index [ :document_id, :block_index, :start_offset ]
      t.index :run_key
      t.index :origin
    end

    create_table :correction_events do |t|
      t.references :document, null: false, foreign_key: true
      t.string :kind, null: false
      t.text :text, null: false
      t.json :replaced
      t.string :ui_event
      t.boolean :from_history, null: false, default: false
      t.string :user_name, null: false
      t.datetime :created_at, null: false
    end
  end
end
