require "test_helper"

class DeleteContentDownloadJobTest < ActiveJob::TestCase
  test "deletes downloaded documents, passages, and map features in batches" do
    download = ContentDownload.create!(resource_id: "huge-package", title: "Huge Package",
      source_url: "https://download.kiwix.org/huge.zim", kind: "zim", status: "complete")
    document = download.documents.create!(title: "Huge", original_filename: "huge.zim",
      content_type: "application/x-openzim", stored_path: "storage/content/zim/huge.zim", status: "ready")
    now = Time.current
    1_005.times.each_slice(500) do |positions|
      document.passages.insert_all!(positions.map { |position| { position:, body: "Body #{position}", created_at: now, updated_at: now } })
    end

    download.enqueue_deletion!
    assert_equal 1_005, download.deletion_total
    DeleteContentDownloadJob.perform_now(download)

    assert_not ContentDownload.exists?(download.id)
    assert_not Document.exists?(document.id)
    assert_equal 0, Passage.where(document_id: document.id).count
  end
end
