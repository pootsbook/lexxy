# Answers "where did this character come from?" For OCR characters that means
# the run and the glyph within it: the engine's confidence and bounding box.
module Document::Traceable
  extend ActiveSupport::Concern

  def origin_at(block_index:, offset:)
    block = content.blocks.fetch(block_index)
    span = provenance_spans.find_by("block_index = ? AND start_offset <= ? AND end_offset > ?", block_index, offset, offset)
    char = Document::Body.utf16_slice(block.text, offset, offset + 1)

    { block: block_index, offset:, char:, origin: span&.origin, by: span&.by, session: span&.session,
      run: span&.run_key, glyph: span && glyph_for(span, offset - span.start_offset) }
  end

  private
    def glyph_for(span, offset_in_span)
      run = OcrRun.find_by(key: span.run_key)
      run && run.glyph_at(span, offset_in_span, spans_of_run: provenance_spans.where(run_key: span.run_key).to_a, blocks: content.blocks)
    end
end
