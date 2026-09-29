# Keeps the citation and provenance tables in step with the body. Rebuilding
# a document's rows on every save is simple and fast enough for chapter-sized
# documents; diff the rows if documents grow to whole books.
module Document::Indexable
  extend ActiveSupport::Concern

  included do
    has_many :citations, dependent: :delete_all
    has_many :provenance_spans, -> { order(:block_index, :start_offset) }, dependent: :delete_all

    before_save :derive_plain_text, if: :body_changed?
    after_save :reindex, if: :saved_change_to_body?
  end

  def reindex
    citation_rows = rows_for("bibleRef") { |attrs| citation_columns(attrs) }
    provenance_rows = rows_for("provenance") { |attrs| provenance_columns(attrs) }

    transaction do
      citations.delete_all
      provenance_spans.delete_all
      Citation.insert_all(citation_rows) if citation_rows.any?
      ProvenanceSpan.insert_all(provenance_rows) if provenance_rows.any?
    end
  end

  private
    def derive_plain_text
      self.plain_text = content.plain_text
    end

    def rows_for(mark_type)
      content.blocks.flat_map do |block|
        block.marks.select { |mark| mark.type == mark_type }.map do |mark|
          { document_id: id, block_index: block.index, start_offset: mark.start, end_offset: mark.end }.merge(yield(mark.attrs))
        end
      end
    end

    def citation_columns(attrs)
      range = Osis.range(attrs["osis"])
      { osis: attrs["osis"], start_verse: range.begin, end_verse: range.end }
    end

    def provenance_columns(attrs)
      { origin: attrs["origin"], run_key: attrs["run"], by: attrs["by"], session: attrs["session"] }
    end
end
