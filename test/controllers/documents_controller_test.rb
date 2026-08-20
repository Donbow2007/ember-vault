require "test_helper"

class DocumentsControllerTest < ActionDispatch::IntegrationTest
  test "combines downloads and imported documents into one inventory without duplicates" do
    download = ContentDownload.create!(resource_id: "downloaded-guide", title: "Downloaded Guide",
      source_url: "https://download.kiwix.org/guide.zim", kind: "zim", status: "complete",
      destination_path: "storage/content/zim/downloaded-guide.zim", downloaded_bytes: 12.megabytes)
    download.documents.create!(title: "Downloaded Guide", original_filename: "downloaded-guide.zim",
      content_type: "application/x-openzim", stored_path: download.destination_path, byte_size: 12.megabytes,
      status: "ready", passage_count: 10)
    Document.create!(title: "Imported Notes", original_filename: "notes.txt", content_type: "text/plain",
      stored_path: "storage/archive_files/notes.txt", byte_size: 100, status: "ready", passage_count: 2)
    map = ContentDownload.create!(resource_id: "downloaded-map", title: "Downloaded Map",
      source_url: "https://example.test/map.pmtiles", kind: "map", status: "complete",
      destination_path: "storage/content/map/downloaded-map.pmtiles", downloaded_bytes: 1.megabyte)
    map.map_features.create!(name: "Test Town", category: "places", kind: "locality",
      latitude: 34.7, longitude: -92.3)
    ContentDownload.create!(resource_id: "smollm2-135m", title: "SmolLM2 Model",
      source_url: "https://huggingface.co/model.gguf", kind: "model", status: "complete",
      destination_path: "storage/models/smollm2-135m.gguf", downloaded_bytes: 102.megabytes)

    get documents_url

    assert_response :success
    assert_select ".unified-inventory .document-table", count: 1
    assert_select ".unified-inventory article", count: 3
    assert_select ".unified-inventory h2", text: "Downloaded Guide", count: 1
    assert_select ".unified-inventory h2", text: "Imported Notes", count: 1
    assert_select ".unified-inventory", text: /SmolLM2 Model/, count: 0
    assert_select "form[action='#{index_content_download_path(download)}']"
    assert_select "form[action='#{reindex_all_downloads_path}']"
    assert_select "form[action='#{reindex_map_path(map)}']"
    assert_select "form.archive-search-input[action='#{search_path}']" do
      assert_select ".search-icon"
      assert_select "input[type='search'][name='q'][placeholder='SEARCH THE ENTIRE ARCHIVE...']"
      assert_select "input[type='submit'][value='SEARCH']"
    end
    assert_select ".inventory-download .index-state", text: "1 MAP NAME"
    assert_select "p.section-index", text: "LOCAL // UNIFIED INVENTORY"
  end

  test "imports, indexes, searches, and removes a text document" do
    upload = fixture_file_upload("survival_notes.txt", "text/plain")

    assert_difference("Document.count", 1) do
      post documents_url, params: { title: "Flood Response", file: upload }
    end

    document = Document.last
    assert_redirected_to document_url(document)
    assert_equal "ready", document.status
    assert_match %r{\Aarchive_files/}, document.stored_path
    assert document.passage_count.positive?

    get search_url, params: { q: "boil drinking water" }
    assert_response :success
    assert_select "mark", minimum: 1
    assert_select "a", text: "Flood Response"

    assert_difference("Document.count", -1) do
      delete document_url(document)
    end
  end

  test "rejects unsupported file formats" do
    upload = fixture_file_upload("survival_notes.txt", "application/octet-stream")
    upload.define_singleton_method(:original_filename) { "notes.exe" }

    assert_no_difference("Document.count") { post documents_url, params: { file: upload } }
    assert_redirected_to documents_url
  end

  test "opens an exact late search passage with nearby context" do
    document = Document.create!(title: "Long Manual", original_filename: "long.zim",
      content_type: "application/x-openzim", stored_path: "storage/content/zim/long.zim",
      byte_size: 1000, status: "ready", passage_count: 130)
    now = Time.current
    document.passages.insert_all!(130.times.map do |position|
      { position:, heading: "Section #{position + 1}", body: "Body for passage #{position + 1}", created_at: now, updated_at: now }
    end)
    target = document.passages.find_by!(position: 120)

    get document_url(document), params: { passage_id: target.id }, headers: { "HTTP_REFERER" => search_url }

    assert_response :success
    assert_select "article#passage-#{target.id}.focused", text: /Body for passage 121/
    assert_select ".passage-reader article", count: 5
    assert_select ".focused-passage-note", text: /PASSAGE 121/
    assert_select "article#passage-#{document.passages.find_by!(position: 0).id}", count: 0
  end

  test "serves an original PDF page as an in-app image" do
    document = Document.create!(title: "PDF Manual", original_filename: "manual.zim",
      content_type: "application/x-openzim", stored_path: "storage/content/zim/manual.zim",
      byte_size: 1000, status: "ready", passage_count: 1)
    passage = document.passages.create!(position: 0, heading: "Page", body: "Page text",
      source_entry_index: 7, source_path: "files/manual.pdf", source_mime: "application/pdf", source_page: 12)
    renderer = Object.new
    renderer.define_singleton_method(:call) { "\x89PNG\r\n".b }

    get document_url(document)
    assert_response :success
    assert_select ".source-pdf-page img[src='#{source_page_document_path(document, passage_id: passage.id)}']"

    original_constructor = PdfPageRenderer.method(:new)
    PdfPageRenderer.define_singleton_method(:new) { |*| renderer }
    get source_page_document_url(document), params: { passage_id: passage.id }

    assert_response :success
    assert_equal "image/png", response.media_type
    assert_equal "\x89PNG\r\n".b, response.body.b
  ensure
    PdfPageRenderer.define_singleton_method(:new, original_constructor) if original_constructor
  end
end
