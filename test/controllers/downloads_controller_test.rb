require "test_helper"

class DownloadsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "searches not-yet-installed bundled resources by topic" do
    get downloads_url, params: { catalog_q: "safe water emergency" }

    assert_response :success
    assert_select ".content-discovery"
    assert_select ".discovery-results article", text: /Make Water Safe During an Emergency/
    assert_select "form[action='#{install_downloads_path}']"
  end

  test "labels remote discovery as public book search" do
    get downloads_url

    assert_response :success
    assert_select ".discovery-source.remote", text: /Search public books/
    assert_select "input[name='remote_q'][placeholder*='PUBLIC BOOKS']"
    assert_select "input[type='submit'][value='SEARCH PUBLIC BOOKS']"
  end

  test "browses available maps by state with coverage, type, size, and install status" do
    installed = ContentDownload.create!(resource_id: "texas", title: "Texas",
      source_url: "https://github.com/Crosstalk-Solutions/project-nomad-maps/raw/refs/heads/master/pmtiles/texas_2025-12.pmtiles",
      kind: "map", status: "complete")

    get downloads_url, params: { map_state: "AR" }

    assert_response :success
    assert_select "select[name='map_state'] option", count: 52
    assert_select "select[name='map_state'] option", text: /District of Columbia — NOT YET AVAILABLE/
    assert_select ".map-discovery .discovery-results article", count: 1
    assert_select ".map-discovery", text: /Arkansas statewide/
    assert_select ".map-discovery", text: /Topographic/
    assert_select ".map-discovery", text: /400 MB/

    get downloads_url, params: { map_state: "TX" }
    assert_select ".map-discovery .discovery-results article", count: 1
    assert_select ".map-discovery .discovery-installed", text: "INSTALLED"
    assert_select ".map-discovery form[action='#{install_downloads_path}']", count: 0
    assert ContentDownload.exists?(installed.id)
  end

  test "installs a signed discovery result through the transfer queue" do
    result = ContentDiscovery::Result.new(resource_id: "discovered-guide", title: "Discovered Guide", creator: "Author",
      description: "Guide", source: "Kiwix catalog", source_url: "https://download.kiwix.org/discovered.zim",
      kind: "zim", size_bytes: 20.megabytes, license: "Source license", coverage: nil, map_type: nil)

    assert_enqueued_with(job: ContentDownloadJob) do
      post install_downloads_url, params: { token: result.token }
    end

    assert_redirected_to downloads_url
    download = ContentDownload.find_by!(resource_id: "discovered-guide")
    assert_equal "queued", download.status
    assert_equal 20.megabytes, download.expected_bytes
  end

  test "rejects an unsigned discovery install" do
    assert_no_difference("ContentDownload.count") do
      post install_downloads_url, params: { token: "untrusted" }
    end

    assert_redirected_to downloads_url
  end

  test "returns failed downloads to the queue" do
    download = ContentDownload.create!(resource_id: "test-zim", title: "Test ZIM",
      source_url: "https://download.kiwix.org/test.zim", kind: "zim", status: "failed", error_message: "redirect")

    assert_enqueued_with(job: ContentDownloadJob, args: [ download ]) do
      post retry_failed_downloads_url
    end

    assert_redirected_to downloads_url
    assert_equal "queued", download.reload.status
    assert_nil download.error_message
  end

  test "serves a live queue without recursive Turbo frames" do
    ContentDownload.create!(resource_id: "queued-zim", title: "Queued ZIM",
      source_url: "https://download.kiwix.org/queued.zim", kind: "zim", status: "queued")

    get downloads_url
    assert_response :success
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_select "meta[name='turbo-cache-control'][content='no-cache']"
    assert_select "div#download_queue[data-controller='download-progress'][data-active='true']"
    assert_select "div#download_queue[data-download-progress-url-value='#{status_downloads_path}']"
    assert_select "turbo-frame#download_queue", count: 0

    get status_downloads_url
    assert_response :success
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_select "[data-downloads-active='true']"
    assert_select "turbo-frame", count: 0
  end

  test "completed downloads always report full progress despite rough catalog estimates" do
    download = ContentDownload.new(status: "complete", expected_bytes: 400.megabytes, downloaded_bytes: 166.megabytes)
    assert_equal 100, download.progress
    assert_equal 166.megabytes, download.display_total_bytes
  end

  test "requests that an active download stop" do
    download = ContentDownload.create!(resource_id: "active-zim", title: "Active ZIM",
      source_url: "https://download.kiwix.org/active.zim", kind: "zim", status: "downloading")

    post stop_download_url(download)

    assert_redirected_to downloads_url
    assert_equal "cancel_requested", download.reload.status
  end

  test "restarts a cancelled download" do
    download = ContentDownload.create!(resource_id: "cancelled-zim", title: "Cancelled ZIM",
      source_url: "https://download.kiwix.org/cancelled.zim", kind: "zim", status: "cancelled",
      downloaded_bytes: 12.megabytes, error_message: "stopped")

    assert_enqueued_with(job: ContentDownloadJob, args: [ download ]) do
      post retry_download_download_url(download)
    end

    assert_redirected_to downloads_url
    assert_equal "queued", download.reload.status
    assert_equal 0, download.downloaded_bytes
    assert_nil download.error_message
  end

  test "deleting a completed download removes its file and indexed documents" do
    download = ContentDownload.create!(resource_id: "delete-zim", title: "Delete ZIM",
      source_url: "https://download.kiwix.org/delete.zim", kind: "zim", status: "complete",
      destination_path: "storage/content/zim/delete-zim.zim")
    content_path = Rails.root.join(download.destination_path)
    FileUtils.mkdir_p(content_path.dirname)
    File.write(content_path, "download")
    document = download.documents.create!(title: "Indexed manual", original_filename: "manual.txt",
      content_type: "text/plain", stored_path: "storage/archive_files/delete-manual.txt", status: "ready")
    document.passages.create!(position: 0, body: "distinctive evacuation instructions")
    Passage.rebuild_search_index
    assert_equal 1, Passage.search("evacuation").size

    assert_enqueued_with(job: DeleteContentDownloadJob) do
      assert_no_difference([ "ContentDownload.count", "Document.count", "Passage.count" ]) do
        delete download_url(download)
      end
    end

    assert_redirected_to downloads_url
    assert_equal "deleting", download.reload.status
    assert File.exist?(content_path), "request must return before file deletion runs"
    perform_enqueued_jobs only: DeleteContentDownloadJob
    assert_not File.exist?(content_path)
    assert_empty Passage.search("evacuation")
  ensure
    File.delete(content_path) if content_path && File.file?(content_path)
  end

  test "deleting an active download asks its worker to purge it" do
    download = ContentDownload.create!(resource_id: "delete-active-zim", title: "Delete Active ZIM",
      source_url: "https://download.kiwix.org/delete-active.zim", kind: "zim", status: "downloading")

    delete download_url(download)

    assert_redirected_to downloads_url
    assert_equal "delete_requested", download.reload.status
  end

  test "shows deletion progress and retry for a failed deletion" do
    download = ContentDownload.create!(resource_id: "failed-delete", title: "Failed Delete",
      source_url: "https://download.kiwix.org/failed.zim", kind: "zim", status: "deletion_failed",
      deletion_total: 100, deletion_remaining: 68, error_message: "local disk busy")

    get status_downloads_url

    assert_response :success
    assert_select ".download-meter", text: /68% REMAINING/
    assert_select "form[action='#{retry_deletion_download_path(download)}']"
    assert_select ".download-list p", text: "local disk busy"
  end

  test "delete all queues completed downloads and requests active transfers to stop" do
    completed = ContentDownload.create!(resource_id: "delete-all-complete", title: "Complete",
      source_url: "https://download.kiwix.org/complete.zim", kind: "zim", status: "complete")
    active = ContentDownload.create!(resource_id: "delete-all-active", title: "Active",
      source_url: "https://download.kiwix.org/active.zim", kind: "zim", status: "downloading")

    assert_enqueued_with(job: DeleteContentDownloadJob, args: [ completed ]) do
      delete destroy_all_downloads_url
    end

    assert_redirected_to downloads_url
    assert_equal "deleting", completed.reload.status
    assert_equal "delete_requested", active.reload.status
    assert ContentDownload.exists?(completed.id)
    assert ContentDownload.exists?(active.id)
  end

  test "queues one completed ZIM for indexing" do
    download = ContentDownload.create!(resource_id: "index-one-zim", title: "Index One ZIM",
      source_url: "https://download.kiwix.org/index-one.zim", kind: "zim", status: "complete",
      destination_path: "storage/content/zim/index-one.zim", downloaded_bytes: 10.megabytes)

    assert_enqueued_with(job: ZimIndexJob) { post index_content_download_url(download) }

    assert_redirected_to documents_url
    assert_equal "queued", download.documents.first.status
  end

  test "queues one completed standalone document for indexing" do
    download = ContentDownload.create!(resource_id: "index-one-pdf", title: "Index One PDF",
      source_url: "https://archive.org/download/manual/manual.pdf", kind: "document", status: "complete",
      destination_path: "storage/content/document/index-one-pdf.pdf", downloaded_bytes: 2.megabytes)

    assert_enqueued_with(job: IndexDocumentJob) { post index_content_download_url(download) }

    assert_redirected_to documents_url
    assert_equal "application/pdf", download.documents.first.content_type
  end

  test "queues all completed ZIM downloads for reindexing but skips maps" do
    zim = ContentDownload.create!(resource_id: "reindex-zim", title: "Reindex ZIM",
      source_url: "https://download.kiwix.org/reindex.zim", kind: "zim", status: "complete",
      destination_path: "storage/content/zim/reindex.zim")
    ContentDownload.create!(resource_id: "reindex-map", title: "Reindex Map",
      source_url: "https://github.com/map.pmtiles", kind: "map", status: "complete",
      destination_path: "storage/content/map/reindex.pmtiles")

    assert_enqueued_jobs 1, only: ZimIndexJob do
      post reindex_all_downloads_url
    end

    assert_redirected_to documents_url
    assert_equal 1, zim.documents.count
  end

  test "removes a download search index without removing its archive" do
    download = ContentDownload.create!(resource_id: "remove-index-zim", title: "Remove Index ZIM",
      source_url: "https://download.kiwix.org/remove-index.zim", kind: "zim", status: "complete",
      destination_path: "storage/content/zim/remove-index.zim")
    archive_path = Rails.root.join(download.destination_path)
    FileUtils.mkdir_p(archive_path.dirname)
    File.write(archive_path, "archive")
    document = download.documents.create!(title: download.title, original_filename: "remove-index.zim",
      content_type: "application/x-openzim", stored_path: download.destination_path, status: "ready", passage_count: 1)
    document.passages.create!(position: 0, heading: "Shelter", body: "unique shelter index text")
    Passage.rebuild_search_index

    assert_enqueued_with(job: DeleteDocumentJob) do
      delete search_index_download_url(download)
    end

    assert_redirected_to documents_url
    assert ContentDownload.exists?(download.id)
    assert File.file?(archive_path)
    assert_equal "deleting", document.reload.status
    perform_enqueued_jobs only: DeleteDocumentJob
    assert_not Document.exists?(document.id)
    assert_empty Passage.search("unique shelter")
  ensure
    File.delete(archive_path) if archive_path && File.file?(archive_path)
  end
end
