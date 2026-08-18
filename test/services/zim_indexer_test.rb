require "test_helper"

class ZimIndexerTest < ActiveSupport::TestCase
  FakeReader = Struct.new(:entries, :contents) do
    def each_readable_entry(&block)
      entries.each(&block)
    end

    def content(entry)
      contents.fetch(entry.index)
    end
  end

  test "extracts readable ZIM articles into searchable passages" do
    download = ContentDownload.create!(resource_id: "field-guide", title: "Field Guide",
      source_url: "https://download.kiwix.org/field-guide.zim", kind: "zim", status: "complete")
    document = download.documents.create!(title: "Field Guide", original_filename: "field-guide.zim",
      content_type: "application/x-openzim", stored_path: "storage/content/zim/field-guide.zim", status: "queued")
    entry = ZimReader::Entry.new(index: 4, path: "water/purification", title: "Purifying Water", mime_type: "text/html")
    reader = FakeReader.new([ entry ], { 4 => "<article><h1>Purifying Water</h1><p>Boil flood water before drinking it.</p></article>" })

    ZimIndexer.new(document, reader:).call

    assert_equal "ready", document.reload.status
    assert document.passage_count.positive?
    result = Passage.search("flood water").first
    assert_equal document, result.document
    assert_equal 4, result.source_entry_index
    assert_equal "water/purification", result.source_path
    assert_equal "text/html", result.source_mime
  end
end
