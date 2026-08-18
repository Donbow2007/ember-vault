class ZimIndexJob < ApplicationJob
  queue_as :default

  def perform(document)
    ZimIndexer.new(document).call
  end
end
