# Finds references like "Rom 8:28", "Romans 8:28-30" or "1 Cor. 13:4" in plain
# text and returns them as OSIS. Deliberately small: for real corpora use a
# full parser (e.g. openbibleinfo's bible-passage-reference-parser), which
# handles many languages, chapter-only references and lists.
class CitationDetector
  NAMES = {
    "Gen" => %w[Genesis Gen], "Exod" => %w[Exodus Exod Ex], "Lev" => %w[Leviticus Lev], "Num" => %w[Numbers Num],
    "Deut" => %w[Deuteronomy Deut Dt], "Josh" => %w[Joshua Josh], "Judg" => %w[Judges Judg], "Ruth" => %w[Ruth],
    "1Sam" => [ "1 Samuel", "1 Sam" ], "2Sam" => [ "2 Samuel", "2 Sam" ], "1Kgs" => [ "1 Kings", "1 Kgs" ], "2Kgs" => [ "2 Kings", "2 Kgs" ],
    "1Chr" => [ "1 Chronicles", "1 Chr" ], "2Chr" => [ "2 Chronicles", "2 Chr" ], "Ezra" => %w[Ezra], "Neh" => %w[Nehemiah Neh],
    "Esth" => %w[Esther Esth], "Job" => %w[Job], "Ps" => %w[Psalms Psalm Ps], "Prov" => %w[Proverbs Prov],
    "Eccl" => %w[Ecclesiastes Eccl], "Song" => [ "Song of Solomon", "Song of Songs", "Song" ], "Isa" => %w[Isaiah Isa],
    "Jer" => %w[Jeremiah Jer], "Lam" => %w[Lamentations Lam], "Ezek" => %w[Ezekiel Ezek], "Dan" => %w[Daniel Dan],
    "Hos" => %w[Hosea Hos], "Joel" => %w[Joel], "Amos" => %w[Amos], "Obad" => %w[Obadiah Obad], "Jonah" => %w[Jonah],
    "Mic" => %w[Micah Mic], "Nah" => %w[Nahum Nah], "Hab" => %w[Habakkuk Hab], "Zeph" => %w[Zephaniah Zeph],
    "Hag" => %w[Haggai Hag], "Zech" => %w[Zechariah Zech], "Mal" => %w[Malachi Mal],
    "Matt" => %w[Matthew Matt Mt], "Mark" => %w[Mark Mk], "Luke" => %w[Luke Lk], "John" => %w[John Jn], "Acts" => %w[Acts],
    "Rom" => %w[Romans Rom], "1Cor" => [ "1 Corinthians", "1 Cor" ], "2Cor" => [ "2 Corinthians", "2 Cor" ],
    "Gal" => %w[Galatians Gal], "Eph" => %w[Ephesians Eph], "Phil" => %w[Philippians Phil], "Col" => %w[Colossians Col],
    "1Thess" => [ "1 Thessalonians", "1 Thess" ], "2Thess" => [ "2 Thessalonians", "2 Thess" ],
    "1Tim" => [ "1 Timothy", "1 Tim" ], "2Tim" => [ "2 Timothy", "2 Tim" ], "Titus" => %w[Titus], "Phlm" => %w[Philemon Phlm],
    "Heb" => %w[Hebrews Heb], "Jas" => %w[James Jas], "1Pet" => [ "1 Peter", "1 Pet" ], "2Pet" => [ "2 Peter", "2 Pet" ],
    "1John" => [ "1 John", "1 Jn" ], "2John" => [ "2 John", "2 Jn" ], "3John" => [ "3 John", "3 Jn" ], "Jude" => %w[Jude],
    "Rev" => %w[Revelation Rev]
  }.freeze

  LOOKUP = NAMES.flat_map { |osis, names| names.map { |name| [ name.downcase, osis ] } }.to_h.freeze

  BOOK_PATTERN = LOOKUP.keys.sort_by { |name| -name.length }.map { |name| Regexp.escape(name).gsub("\\ ") { "\\s?" } }.join("|")

  PATTERN = /
    (?<![[:alnum:]])(?<book>#{BOOK_PATTERN})\.?
    \s+(?<chapter>\d{1,3}):(?<verse>\d{1,3})(?:\s?[-–]\s?(?<end_verse>\d{1,3}))?\b
  /ix

  Match = Data.define(:osis, :start, :end)

  def self.detect(text)
    text.to_enum(:scan, PATTERN).map do
      match = Regexp.last_match
      book = LOOKUP.fetch(match[:book].downcase.gsub(/\s+/, " ").sub(/\A(\d)(?=\S)/, '\1 '))
      osis = "#{book}.#{match[:chapter]}.#{match[:verse]}"
      osis += "-#{book}.#{match[:chapter]}.#{match[:end_verse]}" if match[:end_verse]
      Match.new(osis:, start: match.begin(0), end: match.end(0))
    end
  end
end
