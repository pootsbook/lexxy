class Documents::ProvenancesController < ApplicationController
  def show
    document = Document.find(params[:document_id])
    render json: document.origin_at(block_index: Integer(params.expect(:block)), offset: Integer(params.expect(:offset)))
  rescue IndexError, ArgumentError
    head :not_found
  end
end
