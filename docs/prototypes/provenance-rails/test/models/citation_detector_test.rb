require "test_helper"

class CitationDetectorTest < ActiveSupport::TestCase
  test "finds full names, abbreviations, numbered books and verse ranges" do
    text = "As Romans 8:28-30 says, and 1 Cor. 13:4, 1Cor 1:2, cf. Ps 23:1."

    assert_equal [ "Rom.8.28-Rom.8.30", "1Cor.13.4", "1Cor.1.2", "Ps.23.1" ], CitationDetector.detect(text).map(&:osis)
    assert_equal "Romans 8:28-30", text[CitationDetector.detect(text).first.then { |match| match.start...match.end }]
  end

  test "ignores book names inside other words and unknown books" do
    assert_empty CitationDetector.detect("A remarkable 3:4 ratio, Bob 1:2")
  end
end
