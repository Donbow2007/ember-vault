class MapDownloadJob < ApplicationJob
  queue_as :default

  retry_on Net::OpenTimeout, Net::ReadTimeout, wait: 30.seconds, attempts: 3

  def perform(map_pack)
    MapInstaller.new(map_pack).call
  end
end
