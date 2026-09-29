class Document < ApplicationRecord
  include Indexable, Correctable, Traceable, Printable

  validates :title, presence: true
  validate :body_matches_schema

  scope :matching, ->(query) { where("plain_text LIKE ?", "%#{sanitize_sql_like(query)}%") }

  def content
    @content = Document::Body.new(body) unless @content_source.equal?(body)
    @content_source = body
    @content
  end

  def reading_html
    Document::ReadingHtml.new(content).to_html
  end

  def provenance_summary
    provenance_spans.group(:origin).sum("end_offset - start_offset")
  end

  private
    def body_matches_schema
      if body.blank?
        errors.add(:body, "can't be blank")
      else
        content.errors.each { |message| errors.add(:body, message) }
      end
    end
end
