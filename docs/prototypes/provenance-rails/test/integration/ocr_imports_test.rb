require "test_helper"

class OcrImportsTest < ActionDispatch::IntegrationTest
  setup { ENV["OCR_IMPORT_TOKEN"] = "pipeline-secret" }
  teardown { ENV.delete("OCR_IMPORT_TOKEN") }

  test "the OCR pipeline imports pages with its token" do
    sample = JSON.parse(file_fixture("romans_pages.json").read)

    assert_difference -> { Document.count } => 1, -> { OcrRun.count } => 2 do
      post ocr_imports_path, as: :json, params: sample, headers: { "Authorization" => "Bearer pipeline-secret" }
    end
    assert_response :created
    assert_equal document_url(Document.last), response.parsed_body["url"]
  end

  test "imports without the token are refused" do
    post ocr_imports_path, as: :json, params: { title: "x", pages: [] }, headers: { "Authorization" => "Bearer wrong" }
    assert_response :unauthorized
  end
end
