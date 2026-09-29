class Citation < ApplicationRecord
  belongs_to :document

  scope :overlapping, ->(reference) {
    range = Osis.range(reference)
    where("start_verse <= ? AND end_verse >= ?", range.end, range.begin)
  }

  def snippet(context: 60)
    text = document.content.blocks[block_index].text
    before = Document::Body.utf16_slice(text, [ start_offset - context, 0 ].max, start_offset)
    cited = Document::Body.utf16_slice(text, start_offset, end_offset)
    after = Document::Body.utf16_slice(text, end_offset, [ end_offset + context, Document::Body.utf16_length(text) ].min)
    { before:, cited:, after: }
  end
end
