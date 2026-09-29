require "test_helper"

class Document::TypstSourceTest < ActiveSupport::TestCase
  test "text is emitted as string literals, so markup characters are inert" do
    body = { "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [
      { "type" => "text", "text" => %(#set page(width: 1pt) *not bold* "quoted" \\ // not a comment) },
      { "type" => "text", "text" => "Rom 8:28", "marks" => [ { "type" => "bibleRef", "attrs" => { "osis" => "Rom.8.28" } }, { "type" => "provenance", "attrs" => { "origin" => "human" } } ] }
    ] } ] }

    expected = <<~'TYPST'.chomp
      #"#set page(width: 1pt) *not bold* \"quoted\" \\ // not a comment"#bibleref("Rom.8.28")[#"Rom 8:28"]
    TYPST

    assert_equal expected,
      Document::TypstSource.new(Document::Body.new(body)).to_s
  end

  test "compiles to a PDF, including text full of Typst syntax" do
    skip "Typst CLI not installed (set TYPST)" unless Typst.available?

    document = import_sample
    hostile = { "type" => "paragraph", "content" => [ { "type" => "text", "text" => %(#panic("x") $x^2$ [a] <label> @ref ~ \ "q" /* open) } ] }
    document.update!(body: document.body.merge("content" => document.body["content"] + [ hostile ]))

    assert document.to_pdf.start_with?("%PDF-")
  end
end
