require "test_helper"

class DocumentsTest < ActionDispatch::IntegrationTest
  setup do
    @document = import_sample
    ActionController::Base.allow_forgery_protection = false
  end

  teardown { ActionController::Base.allow_forgery_protection = true }

  test "saving from the editor attributes events to the session user, not the payload" do
    patch session_path, params: { user_name: "ruth" }
    body = @document.body.deep_dup
    body["content"][0]["content"][0]["text"].sub!("togther", "together")

    patch document_path(@document, format: :json), as: :json,
      params: { document: { body: }, events: [ { type: "insert", text: "e", uiEvent: nil, fromHistory: false }, { type: "insert", text: "x", fromHistory: true } ] }

    assert_response :success
    assert_includes @document.reload.plain_text, "work together"
    assert_equal [ "ruth" ], @document.correction_events.distinct.pluck(:user_name)
    assert_equal 1, @document.correction_events.corrections.count
  end

  test "an invalid body is refused with the validation errors" do
    patch document_path(@document, format: :json), as: :json, params: { document: { body: { type: "doc", content: [ { type: "iframe" } ] } } }

    assert_response :unprocessable_content
    assert_equal [ %(Body unknown node type "iframe") ], response.parsed_body["errors"]
  end

  test "reading page, provenance lookup, citation search, Typst and PDF" do
    get document_path(@document)
    assert_select "cite.bible-ref[data-osis='Rom.8.28']", "Rom 8:28"
    assert_select ".reading [data-origin]", 0

    get document_provenance_path(@document, format: :json), params: { block: 0, offset: 0 }
    assert_equal [ "A", "tesseract", 42 ], response.parsed_body.values_at("char", "origin").push(response.parsed_body.dig("glyph", "page"))

    get document_provenance_path(@document, format: :json), params: { block: 99, offset: 0 }
    assert_response :not_found

    get citations_path, params: { ref: "Rom.8.29" }
    assert_select ".citations li", 1
    assert_select ".citations mark", "Romans 8:29-30"

    get citations_path, params: { ref: "Bob.1" }
    assert_select ".error", /unknown book/

    get document_path(@document, format: :typ)
    assert_includes response.body, %(#bibleref("Rom.8.28")[#"Rom 8:28"])

    if Typst.available?
      get document_path(@document, format: :pdf)
      assert_equal "application/pdf", response.media_type
    end
  end
end
