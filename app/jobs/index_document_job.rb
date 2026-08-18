class IndexDocumentJob < ApplicationJob
  queue_as :default

  def perform(document)
    DocumentIndexer.new(document).call
  end
end
