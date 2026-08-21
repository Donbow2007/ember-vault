class KnowledgePackIndexJob < ApplicationJob
  queue_as :default

  def perform(download, backup_path = "")
    download.update!(status: "indexing", error_message: nil)
    KnowledgePackageInstaller.new(download).finalize(backup_path:)
  rescue StandardError => error
    download.update(status: "failed", error_message: error.message.to_s.first(500))
    raise
  end
end
