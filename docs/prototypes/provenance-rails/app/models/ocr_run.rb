# One engine's pass over one page. `glyphs` holds a record per character of
# `text`: the word it belongs to, the engine's confidence, the bounding box.
class OcrRun < ApplicationRecord
  ENGINES = %w[ tesseract llm ].freeze

  validates :key, :text, presence: true
  validates :engine, inclusion: { in: ENGINES }
  validate :one_glyph_per_character

  # After editing, a run survives as spans whose text is a subsequence of the
  # original: humans can delete OCR characters but inserted characters get
  # their own provenance. So each surviving character is matched greedily
  # against the run's text, in document order. Ambiguity is limited to which
  # of two identical adjacent characters was deleted.
  def glyph_at(span, offset_in_span, spans_of_run:, blocks:)
    alignment = align(spans_of_run, blocks)
    index = alignment.dig(span.id, offset_in_span)
    index && glyphs[index].merge("index" => index, "engine" => engine, "engine_version" => engine_version, "page" => page)
  end

  private
    def align(spans, blocks)
      characters = text.each_char.to_a
      cursor = 0

      spans.to_h do |span|
        span_text = Document::Body.utf16_slice(blocks[span.block_index].text, span.start_offset, span.end_offset)
        indexes = match(span_text.each_char.to_a, characters, cursor) || match(span_text.each_char.to_a, characters, 0) || []
        cursor = indexes.last + 1 if indexes.any?
        [ span.id, utf16_offsets(span_text).zip(indexes).to_h ]
      end
    end

    def match(needle, haystack, from)
      position = from
      needle.map do |char|
        position += 1 while position < haystack.size && haystack[position] != char
        return nil if position >= haystack.size
        position.tap { position += 1 }
      end
    end

    def utf16_offsets(string)
      offset = 0
      string.each_char.map { |char| offset.tap { offset += Document::Body.utf16_length(char) } }
    end

    def one_glyph_per_character
      errors.add(:glyphs, "must have one entry per character") unless glyphs.is_a?(Array) && glyphs.size == text.to_s.each_char.count
    end
end
