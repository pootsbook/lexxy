# The editor reports every insertion and deletion with the provenance of what
# was replaced. They arrive with the save that contains them, and the user is
# taken from the session, never from the client payload.
module Document::Correctable
  extend ActiveSupport::Concern

  included do
    has_many :correction_events, dependent: :delete_all
  end

  def revise(body:, events:, user_name:)
    transaction do
      update!(body:)
      record_corrections(events, user_name:)
    end
  end

  private
    def record_corrections(events, user_name:)
      rows = Array(events).filter_map { |event| correction_row(event.to_h.deep_stringify_keys, user_name) }
      CorrectionEvent.insert_all(rows) if rows.any?
    end

    def correction_row(event, user_name)
      case event["type"]
      when "insert"
        base_row(event, user_name).merge(kind: "insert", text: event["text"].to_s, replaced: nil)
      when "delete"
        pieces = Array(event["pieces"]).map { |piece| piece.to_h.slice("text", "provenance") }
        base_row(event, user_name).merge(kind: "delete", text: pieces.sum("") { |piece| piece["text"].to_s }, replaced: pieces)
      end
    end

    def base_row(event, user_name)
      { document_id: id, ui_event: event["uiEvent"], from_history: event["fromHistory"] == true, user_name:, created_at: Time.current }
    end
end
