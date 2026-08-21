class KnowledgePackIndexJob < ApplicationJob
  queue_as :default

  def perform(download)
    download.documents.order(:id).find_each do |document|
      DocumentIndexer.new(document, rebuild_search_index: false).call
      raise document.error_message if document.reload.status == "failed"
    end
    Passage.rebuild_search_index
  end
end
