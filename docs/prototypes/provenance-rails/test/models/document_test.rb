require "test_helper"

class DocumentTest < ActiveSupport::TestCase
  test "a human correction is indexed, attributed and logged" do
    document = import_sample
    correct(document, find: "togther", replace_with: "together")

    assert_includes paragraph_text(document), "work together for good"
    assert_equal 8, document.provenance_summary["human"]
    assert_equal [ "ruth" ], document.provenance_spans.where(origin: "human").pluck(:by)

    deletion, insertion = document.correction_events.order(:id)
    assert_equal [ "delete", "togther", "tesseract" ], [ deletion.kind, deletion.text, deletion.replaced.first.dig("provenance", "origin") ]
    assert_equal [ "insert", "together", "ruth" ], [ insertion.kind, insertion.text, insertion.user_name ]
  end

  test "origin_at traces OCR characters to their glyph, even after nearby edits" do
    document = import_sample
    correct(document, find: "tog", replace_with: "toge")
    text = paragraph_text(document)

    human = document.origin_at(block_index: 0, offset: text.index("toge"))
    assert_equal [ "t", "human", "ruth", nil ], human.values_at(:char, :origin, :by, :glyph)

    after = document.origin_at(block_index: 0, offset: text.index("ther for"))
    assert_equal [ "t", "tesseract" ], after.values_at(:char, :origin)
    assert_equal({ "word" => "togther", "conf" => 91.0, "engine" => "tesseract", "page" => 42 }, after[:glyph].slice("word", "conf", "engine", "page"))
    assert_equal "t", OcrRun.find_by(engine: "tesseract").text[after[:glyph]["index"]]
  end

  test "deleting OCR characters keeps later glyphs aligned" do
    document = import_sample
    correct(document, find: "all ", replace_with: "")

    offset = paragraph_text(document).index("things")
    glyph = document.origin_at(block_index: 0, offset:)[:glyph]
    assert_equal [ "t", "things" ], glyph.values_at("char", "word")
  end

  test "rejects an invalid body without touching the indexes" do
    document = import_sample

    assert_raises(ActiveRecord::RecordInvalid) do
      document.revise(body: { "type" => "doc", "content" => [ { "type" => "iframe" } ] }, events: [], user_name: "ruth")
    end
    assert_equal 4, document.citations.count
  end

  test "finds documents by citation range and by text" do
    document = import_sample

    assert_equal [ "Rom.8.28", "Rom.8.29-Rom.8.30" ], Citation.overlapping("Rom.8").order(:start_verse).pluck(:osis)
    assert_equal [ "Rom.8.29-Rom.8.30" ], Citation.overlapping("Rom.8.30-Rom.9.1").pluck(:osis)
    assert_empty Citation.overlapping("Rom.9")
    assert_equal [ document ], Document.matching("predestinate").to_a
    assert_empty Document.matching("%")
  end
end
