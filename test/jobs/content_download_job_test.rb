require "test_helper"

class ContentDownloadJobTest < ActiveJob::TestCase
  include ActiveJob::TestHelper

  test "completed ZIM downloads can enqueue a linked search document" do
    download = ContentDownload.create!(resource_id: "indexable-zim", title: "Indexable ZIM",
      source_url: "https://download.kiwix.org/indexable.zim", kind: "zim", status: "complete",
      destination_path: "storage/content/zim/indexable-zim.zim", downloaded_bytes: 20.megabytes)

    assert_enqueued_with(job: ZimIndexJob) { download.enqueue_indexing! }

    assert_equal 1, download.documents.count
    document = download.documents.first
    assert_equal "queued", document.status
    assert_equal "application/x-openzim", document.content_type
    assert_equal download.destination_path, document.stored_path
  end

  # test "the truth" do
  #   assert true
  # end
end
