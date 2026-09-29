# OSIS references ("Rom.8.28", "Rom.8.28-Rom.8.30", "Rom.8") as integer verse
# ranges, so citation search is a range-overlap query. A verse id is
# book * 1_000_000 + chapter * 1_000 + verse; a chapter-only reference spans
# verses 1..999 and a book-only reference spans every chapter.
module Osis
  BOOKS = %w[
    Gen Exod Lev Num Deut Josh Judg Ruth 1Sam 2Sam 1Kgs 2Kgs 1Chr 2Chr Ezra Neh Esth Job Ps Prov Eccl Song
    Isa Jer Lam Ezek Dan Hos Joel Amos Obad Jonah Mic Nah Hab Zeph Hag Zech Mal
    Matt Mark Luke John Acts Rom 1Cor 2Cor Gal Eph Phil Col 1Thess 2Thess 1Tim 2Tim Titus Phlm Heb Jas
    1Pet 2Pet 1John 2John 3John Jude Rev
  ].freeze

  class InvalidReference < ArgumentError; end

  extend self

  def range(reference)
    first, last = reference.to_s.split("-", 2)
    start_verse, end_verse = bounds(first)
    end_verse = bounds(last, book: book_of(first)).last if last
    raise InvalidReference, "#{reference} ends before it starts" if end_verse < start_verse

    start_verse..end_verse
  end

  def valid?(reference)
    range(reference)
    true
  rescue InvalidReference
    false
  end

  private
    def bounds(part, book: nil)
      segments = part.to_s.split(".")
      segments.unshift(book) if book && !BOOKS.include?(segments.first)
      name, chapter, verse = segments
      number = BOOKS.index(name) or raise InvalidReference, "unknown book in #{part.inspect}"

      if verse
        id = verse_id(number, chapter, verse)
        [ id, id ]
      elsif chapter
        [ verse_id(number, chapter, 1), verse_id(number, chapter, 999) ]
      else
        [ verse_id(number, 1, 1), verse_id(number, 999, 999) ]
      end
    end

    def book_of(part)
      part.to_s.split(".").first
    end

    def verse_id(book_number, chapter, verse)
      chapter, verse = Integer(chapter, exception: false), Integer(verse, exception: false)
      raise InvalidReference, "chapter and verse must be numbers" unless chapter&.positive? && verse&.positive?

      (book_number + 1) * 1_000_000 + chapter * 1_000 + verse
    end
end
