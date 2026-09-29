require "test_helper"

class Document::ReadingHtmlTest < ActiveSupport::TestCase
  test "keeps structure and citations but drops provenance" do
    html = import_sample.reading_html

    assert_includes html, %(<cite class="bible-ref" data-osis="Rom.8.28">Rom 8:28</cite>)
    assert_no_match(/data-origin|tesseract|provenance/, html)
    assert_equal 3, html.scan("<p>").size
  end

  test "escapes text and renders marks and blocks" do
    body = { "type" => "doc", "content" => [
      { "type" => "heading", "attrs" => { "level" => 2 }, "content" => [ { "type" => "text", "text" => "<script>" } ] },
      { "type" => "orderedList", "attrs" => { "start" => 3 }, "content" => [ { "type" => "listItem", "content" => [
        { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "go", "marks" => [ { "type" => "bold" }, { "type" => "link", "attrs" => { "href" => "https://example.com" } } ] } ] } ] } ] }
    ] }

    assert_equal %(<h2>&lt;script&gt;</h2><ol start="3"><li><p><strong><a href="https://example.com" rel="noopener noreferrer nofollow">go</a></strong></p></li></ol>),
      Document::ReadingHtml.new(Document::Body.new(body)).to_html
  end
end
