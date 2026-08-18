require "net/http"

class ContentDownloadJob < ApplicationJob
  queue_as :default

  retry_on Net::OpenTimeout, Net::ReadTimeout, wait: 30.seconds, attempts: 3

  def perform(download)
    ContentFetcher.new(download).call
  end
end
