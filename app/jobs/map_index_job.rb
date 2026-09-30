class MapIndexJob < ApplicationJob
  queue_as :default

  def perform(map_pack)
    MapIndexer.new(map_pack).call
  end
end
