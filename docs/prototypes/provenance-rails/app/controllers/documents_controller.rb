class DocumentsController < ApplicationController
  before_action :set_document, except: :index

  def index
    @documents = Document.order(updated_at: :desc)
    @documents = @documents.matching(params[:q]) if params[:q].present?
  end

  def show
    respond_to do |format|
      format.html
      format.json { render json: { id: @document.id, title: @document.title, body: @document.body, blocks: @document.content.blocks.map(&:to_h) } }
      format.typ { render plain: @document.to_typst, content_type: "text/x-typst" }
      format.pdf { send_data @document.to_pdf, filename: "#{@document.title.parameterize}.pdf", type: :pdf, disposition: :inline }
    end
  end

  def edit
  end

  # The editor posts { document: { body: <ProseMirror JSON> }, events: [...] }.
  # The body is untrusted: Document::Body validates every node, mark and attr.
  def update
    payload = request.request_parameters
    @document.revise(body: payload.dig("document", "body"), events: payload["events"], user_name: Current.user_name)
    render json: { saved_at: @document.updated_at, provenance: @document.provenance_summary }
  rescue ActiveRecord::RecordInvalid
    render json: { errors: @document.errors.full_messages }, status: :unprocessable_content
  end

  private
    def set_document
      @document = Document.find(params[:id])
    end
end
