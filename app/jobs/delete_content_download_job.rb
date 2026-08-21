class DeleteContentDownloadJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 1_000

  def perform(download)
    return unless download.persisted?

    prepare(download)
    delete_passages(download)
    delete_map_features(download)
    download.documents.find_each(&:destroy!)
    download.remove_content_files
    download.destroy!
  rescue ActiveRecord::RecordNotFound
    nil
  rescue StandardError => error
    Rails.logger.error("Content download deletion failed for #{download.id}: #{error.class}: #{error.message}")
    download.update(status: "deletion_failed", error_message: error.message.to_s.first(500)) if download.persisted?
  end

  private

  def prepare(download)
    return if download.status == "deleting" && download.deletion_total.to_i.positive?

    total = Passage.where(document_id: download.documents.select(:id)).count
    download.update!(status: "deleting", deletion_total: total, deletion_remaining: total, error_message: nil)
  end

  def delete_passages(download)
    scope = Passage.where(document_id: download.documents.select(:id))
    loop do
      ids = scope.limit(BATCH_SIZE).pluck(:id)
      break if ids.empty?

      Passage.where(id: ids).delete_all
      download.update_columns(deletion_remaining: scope.count, updated_at: Time.current)
    end
  end

  def delete_map_features(download)
    loop do
      ids = download.map_features.limit(BATCH_SIZE).pluck(:id)
      break if ids.empty?

      MapFeature.where(id: ids).delete_all
    end
  end
end
