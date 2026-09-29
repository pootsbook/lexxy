# Machine clients (the OCR pipeline) post JSON with a bearer token instead of
# a browser session, so forgery protection gives way to token authentication.
class OcrImportsController < ApplicationController
  skip_forgery_protection
  before_action :authenticate_pipeline

  def create
    import = OcrImport.new(request.request_parameters.slice("title", "pages"))

    if import.save
      render json: { id: import.document.id, url: document_url(import.document) }, status: :created
    else
      render json: { errors: import.errors.full_messages }, status: :unprocessable_content
    end
  end

  private
    def authenticate_pipeline
      expected = ENV["OCR_IMPORT_TOKEN"].to_s
      authenticate_or_request_with_http_token do |token|
        expected.present? && ActiveSupport::SecurityUtils.secure_compare(token, expected)
      end
    end
end
