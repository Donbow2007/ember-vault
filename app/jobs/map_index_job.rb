class MapIndexJob < ApplicationJob
  queue_as :default

  def perform(map_pack)
    return unless map_pack.pack_path.file?

    MapIndexer.new(map_pack).call
  end
end
