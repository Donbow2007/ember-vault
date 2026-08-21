class DeleteDocumentJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 1_000

  def perform(document)
    return unless document.persisted?

    prepare(document)
    loop do
      ids = document.passages.limit(BATCH_SIZE).pluck(:id)
      break if ids.empty?

      Passage.where(id: ids).delete_all
      remaining = document.passages.count
      document.update_columns(deletion_remaining: remaining, updated_at: Time.current)
    end
    document.destroy!
  rescue ActiveRecord::RecordNotFound
    nil
  rescue StandardError => error
    Rails.logger.error("Document deletion failed for #{document.id}: #{error.class}: #{error.message}")
    document.update(status: "deletion_failed", error_message: error.message.to_s.first(500)) if document.persisted?
  end

  private

  def prepare(document)
    return if document.status == "deleting" && document.deletion_total.to_i.positive?

    total = document.passages.count
    document.update!(status: "deleting", deletion_total: total, deletion_remaining: total, error_message: nil)
  end
end
