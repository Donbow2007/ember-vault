class MapIndexJob < ApplicationJob
  queue_as :default

  def perform(download)
    MapIndexer.new(download).call
  end
end
