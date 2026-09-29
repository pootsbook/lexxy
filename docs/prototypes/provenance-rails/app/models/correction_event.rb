class CorrectionEvent < ApplicationRecord
  belongs_to :document

  scope :corrections, -> { where(from_history: false) }
end
