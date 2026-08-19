class AssistantResponse < ApplicationRecord
  STATUSES = %w[queued running cancel_requested cancelled complete failed].freeze

  serialize :source_passage_ids, coder: JSON, type: Array
  attribute :source_passage_ids, default: -> { [] }

  validates :question, presence: true, length: { maximum: 500 }
  validates :status, inclusion: { in: STATUSES }

  def pending?
    queued? || running? || cancel_requested?
  end

  def queued?
    status == "queued"
  end

  def running?
    status == "running"
  end

  def cancel_requested?
    status == "cancel_requested"
  end

  def cancelled?
    status == "cancelled"
  end

  def complete?
    status == "complete"
  end

  def failed?
    status == "failed"
  end

  def sources
    @sources ||= begin
      indexed = Passage.includes(:document).where(id: source_passage_ids).index_by { |passage| passage.id.to_s }
      source_passage_ids.filter_map { |id| indexed[id.to_s] }
    end
  end
end
