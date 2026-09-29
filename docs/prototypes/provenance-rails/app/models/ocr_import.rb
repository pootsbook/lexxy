# Turns engine output into a document: one OcrRun per page and engine, and a
# body whose text carries provenance marks pointing at those runs. Detected
# citations become bibleRef marks. Expected input:
#
#   { title:, pages: [ { page:, engine:, engine_version:,
#       paragraphs: [ [ { text:, conf:, bbox: [x0, y0, x1, y1] }, ... ], ... ] } ] }
class OcrImport
  include ActiveModel::Model

  attr_accessor :title, :pages

  validates :title, presence: true
  validate :pages_present

  def save
    return false unless valid?

    ActiveRecord::Base.transaction do
      paragraphs = Array(pages).flat_map { |page| import_page(page.to_h.deep_stringify_keys) }
      @document = Document.create!(title:, body: { "type" => "doc", "content" => paragraphs })
    end
  end

  def save!
    save || raise(ActiveModel::ValidationError, self)
  end

  def document
    @document
  end

  private
    def import_page(page)
      key = "#{page["engine"]}-p#{page["page"]}-#{SecureRandom.alphanumeric(6).downcase}"
      paragraphs = Array(page["paragraphs"]).map { |words| words.map(&:to_h) }
      run = OcrRun.create!(key:, engine: page["engine"], engine_version: page["engine_version"], page: page["page"],
        text: paragraphs.map { |words| words.map { |word| word["text"] }.join(" ") }.join("\n"),
        glyphs: glyphs_for(paragraphs))

      paragraphs.map { |words| paragraph(words.map { |word| word["text"] }.join(" "), run) }
    end

    # One glyph per character of the run text. Engines usually report
    # confidence per word, so characters inherit their word's.
    def glyphs_for(paragraphs)
      paragraphs.each_with_index.flat_map do |words, paragraph_index|
        separator = paragraph_index.zero? ? [] : [ { "separator" => "paragraph" } ]
        separator + words.each_with_index.flat_map do |word, word_index|
          space = word_index.zero? ? [] : [ { "separator" => "space" } ]
          space + word["text"].each_char.map { |char| { "char" => char, "word" => word["text"], "conf" => word["conf"], "bbox" => word["bbox"] } }
        end
      end
    end

    def paragraph(text, run)
      provenance = { "type" => "provenance", "attrs" => { "origin" => run.engine, "run" => run.key, "by" => nil, "session" => nil } }
      { "type" => "paragraph", "content" => segments(text).map { |segment, osis|
        marks = [ provenance ]
        marks.unshift({ "type" => "bibleRef", "attrs" => { "osis" => osis } }) if osis
        { "type" => "text", "text" => segment, "marks" => marks }
      } }
    end

    def segments(text)
      position = 0
      CitationDetector.detect(text).flat_map { |match|
        before = text[position...match.start]
        position = match.end
        [ ([ before, nil ] if before.present?), [ text[match.start...match.end], match.osis ] ].compact
      }.tap { |pieces| pieces << [ text[position..], nil ] if position < text.length }
    end

    def pages_present
      errors.add(:pages, "must include at least one page with text") if Array(pages).none? { |page| Array(page.to_h.stringify_keys["paragraphs"]).any? }
    end
end
