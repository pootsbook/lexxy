require "test_helper"

class OcrImportTest < ActiveSupport::TestCase
  test "creates a run per page and engine, with one glyph per character" do
    document = import_sample
    runs = OcrRun.order(:page)

    assert_equal [ [ "tesseract", 42 ], [ "llm", 43 ] ], runs.pluck(:engine, :page)
    runs.each { |run| assert_equal run.text.each_char.count, run.glyphs.size }
    assert_equal({ "tesseract" => 154, "llm" => 68 }, document.provenance_summary)
  end

  test "detected citations become bibleRef marks and index rows" do
    document = import_sample

    assert_equal [ "Rom.8.28", "1Cor.2.9", "Ps.23.1", "Rom.8.29-Rom.8.30" ], document.citations.order(:block_index, :start_offset).pluck(:osis)
    assert_equal "Rom 8:28", document.citations.find_by(osis: "Rom.8.28").snippet[:cited]
  end

  test "requires a title and some text" do
    import = OcrImport.new(title: "", pages: [ { page: 1, engine: "tesseract", paragraphs: [] } ])

    assert_not import.save
    assert_equal [ "Title can't be blank", "Pages must include at least one page with text" ], import.errors.full_messages
  end
end
