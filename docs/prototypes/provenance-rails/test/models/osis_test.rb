require "test_helper"

class OsisTest < ActiveSupport::TestCase
  test "verses, ranges, chapters and books become verse id ranges" do
    assert_equal 45_008_028..45_008_028, Osis.range("Rom.8.28")
    assert_equal 45_008_028..45_008_030, Osis.range("Rom.8.28-Rom.8.30")
    assert_equal 45_008_028..45_008_030, Osis.range("Rom.8.28-8.30")
    assert_equal 45_008_001..45_008_999, Osis.range("Rom.8")
    assert_equal 45_001_001..45_999_999, Osis.range("Rom")
    assert_equal 46_013_004..46_013_004, Osis.range("1Cor.13.4")
  end

  test "rejects unknown books, non-numbers and backwards ranges" do
    assert_raises(Osis::InvalidReference) { Osis.range("Bob.1.1") }
    assert_raises(Osis::InvalidReference) { Osis.range("Rom.eight.28") }
    assert_raises(Osis::InvalidReference) { Osis.range("Rom.8.30-Rom.8.28") }
    assert_not Osis.valid?("")
  end
end
