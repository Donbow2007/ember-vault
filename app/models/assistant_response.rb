class AssistantResponse < ApplicationRecord
  STATUSES = %w[queued running cancel_requested cancelled complete failed].freeze


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

end
