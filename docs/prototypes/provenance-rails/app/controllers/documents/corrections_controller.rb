class Documents::CorrectionsController < ApplicationController
  def index
    @document = Document.find(params[:document_id])
    @corrections = @document.correction_events.corrections.order(created_at: :desc, id: :desc).limit(200)
  end
end
