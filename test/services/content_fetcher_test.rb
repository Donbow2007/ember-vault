require "test_helper"

class ContentFetcherTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  test "accepts trusted origins and public HTTPS redirect hosts" do
    fetcher = ContentFetcher.new(ContentDownload.new, resolver: ->(_) { [ "8.8.8.8" ] })
    assert_nil fetcher.send(:validate_uri!, URI("https://download.kiwix.org/file.zim"), initial: true)
    assert_nil fetcher.send(:validate_uri!, URI("https://archive.download.kiwix.org/zim/zimit1/file.zim"), initial: true)
    assert_nil fetcher.send(:validate_uri!, URI("https://archive.org/download/item/file.pdf"), initial: true)
    assert_nil fetcher.send(:validate_uri!, URI("https://www.gutenberg.org/ebooks/2017.txt.utf-8"), initial: true)
    assert_nil fetcher.send(:validate_uri!, URI("https://www.ncbi.nlm.nih.gov/research/article"), initial: true)
    assert_nil fetcher.send(:validate_uri!, URI("https://media.githubusercontent.com/file.pmtiles"))
  end

  test "rejects arbitrary origins and private redirect addresses" do
    public_fetcher = ContentFetcher.new(ContentDownload.new, resolver: ->(_) { [ "8.8.8.8" ] })
    assert_raises(RuntimeError) { public_fetcher.send(:validate_uri!, URI("https://example.com/file"), initial: true) }

    private_fetcher = ContentFetcher.new(ContentDownload.new, resolver: ->(_) { [ "127.0.0.1" ] })
    assert_raises(RuntimeError) { private_fetcher.send(:validate_uri!, URI("https://redirect.example/file")) }
  end

  test "honors a stop request before opening the network" do
    download = ContentDownload.create!(resource_id: "stop-before-fetch", title: "Stop Before Fetch",
      source_url: "https://download.kiwix.org/stop.zim", kind: "zim", status: "cancel_requested")

    ContentFetcher.new(download).call

    assert_equal "cancelled", download.reload.status
    assert_equal 0, download.downloaded_bytes
  end

  test "honors a deletion request before opening the network" do
    download = ContentDownload.create!(resource_id: "delete-before-fetch", title: "Delete Before Fetch",
      source_url: "https://download.kiwix.org/delete.zim", kind: "zim", status: "delete_requested")

    assert_enqueued_with(job: DeleteContentDownloadJob, args: [ download ]) do
      ContentFetcher.new(download).call
    end
    assert_equal "deleting", download.reload.status
    assert ContentDownload.exists?(download.id)
  end

  test "rejects curated content whose downloaded bytes do not match its manifest checksum" do
    download = ContentDownload.new(resource_id: "religion-buddhism-dhammapada-muller")
    file = Tempfile.new
    file.write("tampered")
    file.close

    error = assert_raises(RuntimeError) { ContentFetcher.new(download).send(:verify_checksum!, Pathname(file.path)) }
    assert_match "checksum", error.message
  ensure
    file&.unlink
  end
end
