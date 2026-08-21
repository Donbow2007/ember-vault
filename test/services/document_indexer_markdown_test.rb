require "test_helper"

class DocumentIndexerMarkdownTest < ActiveSupport::TestCase
  test "preserves article and section headings for weighted local search" do
    path = EmberVault::Paths.archive_files.join("indexer-markdown-test.md")
    FileUtils.mkdir_p(path.dirname)
    File.write(path, <<~MARKDOWN)
      # Pressure Bandages

      A pressure bandage controls serious external bleeding.

      ## Application

      1. Place a sterile dressing over the wound.
      2. Wrap firmly enough to maintain pressure.

      ## Reassessment

      Check circulation beyond the bandage frequently.
    MARKDOWN
    document = Document.create!(title: "Pressure Bandages", original_filename: "pressure-bandages/article.md",
      content_type: "text/markdown", stored_path: EmberVault::Paths.relative(path), status: "queued")

    DocumentIndexer.new(document, rebuild_search_index: false).call

    assert_equal "ready", document.reload.status
    assert_includes document.passages.pluck(:heading), "Pressure Bandages — Application"
    assert_includes document.passages.pluck(:heading), "Pressure Bandages — Reassessment"
  ensure
    File.delete(path) if path && path.file?
  end
end
