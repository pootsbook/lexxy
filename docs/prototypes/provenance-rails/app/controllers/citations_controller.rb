class CitationsController < ApplicationController
  def index
    @reference = params[:ref].to_s.strip
    @citations = @reference.present? ? Citation.overlapping(@reference).includes(:document).order(:document_id, :block_index, :start_offset) : Citation.none
  rescue Osis::InvalidReference => error
    @error = error.message
    @citations = Citation.none
  end
end
