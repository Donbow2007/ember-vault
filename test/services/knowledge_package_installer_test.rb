require "test_helper"
require "zip"

class KnowledgePackageInstallerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "creates one indexable document per canonical article" do
    package_id = "test-pack-#{SecureRandom.hex(4)}"
    archive = EmberVault::Paths.content_for("knowledge-pack").join("#{package_id}.zip")
    FileUtils.mkdir_p(archive.dirname)
    Zip::File.open(archive, create: true) do |zip|
      zip.get_output_stream("bowline/article.md") { |io| io.write("# Bowline\n\n## Steps\n\n1. Form a loop.") }
      zip.get_output_stream("bowline/metadata.json") { |io| io.write({ id: "article-bowline", slug: "bowline", title: "Bowline", category: "knots", version: 1, content_hash: "a" * 64 }.to_json) }
      zip.get_output_stream("clove-hitch/article.md") { |io| io.write("# Clove Hitch\n\n## Steps\n\n1. Cross the rope.") }
      zip.get_output_stream("clove-hitch/metadata.json") { |io| io.write({ id: "article-clove", slug: "clove-hitch", title: "Clove Hitch", category: "knots", version: 1, content_hash: "b" * 64 }.to_json) }
    end
    download = ContentDownload.create!(resource_id: "knowledge-pack:#{package_id}", package_id:, package_version: 1,
      content_hash: Digest::SHA256.file(archive).hexdigest, title: "Knots", source_url: "https://example.com/knots.zip",
      kind: "knowledge-pack", status: "complete", destination_path: EmberVault::Paths.relative(archive))

    perform_enqueued_jobs { KnowledgePackageInstaller.new(download).call }

    assert_equal 2, download.documents.count
    assert_equal [ "Bowline", "Clove Hitch" ], download.documents.order(:title).pluck(:title)
    assert download.documents.all? { |document| document.content_type == "text/markdown" }
  ensure
    File.delete(archive) if archive && archive.file?
  end

  test "rejects checksum mismatches without replacing installed documents" do
    package_id = "checksum-pack-#{SecureRandom.hex(4)}"
    archive = build_archive(package_id, "article-id", "Original")
    download = package_download(package_id, archive, content_hash: "0" * 64)
    existing = download.documents.create!(external_id: "article-id", title: "Working copy", original_filename: "old/article.md",
      content_type: "text/markdown", stored_path: EmberVault::Paths.relative(archive), status: "ready")
    assert_raises(RuntimeError) { KnowledgePackageInstaller.new(download).call }
    assert_equal "Working copy", existing.reload.title
  ensure
    File.delete(archive) if archive&.file?
  end

  test "rejects zip path traversal" do
    package_id = "traversal-pack-#{SecureRandom.hex(4)}"
    archive = EmberVault::Paths.content_for("knowledge-pack").join("#{package_id}.zip")
    Zip::File.open(archive, create: true) { |zip| zip.get_output_stream("../escape.txt") { |io| io.write("unsafe") } }
    download = package_download(package_id, archive)
    assert_raises(RuntimeError) { KnowledgePackageInstaller.new(download).call }
  ensure
    File.delete(archive) if archive&.file?
  end

  test "reinstallation updates the stable article instead of duplicating it" do
    package_id = "update-pack-#{SecureRandom.hex(4)}"
    archive = build_archive(package_id, "stable-article", "Version One")
    download = package_download(package_id, archive)
    perform_enqueued_jobs { KnowledgePackageInstaller.new(download).call }
    first_id = download.documents.first.id
    File.delete(archive)
    archive = build_archive(package_id, "stable-article", "Version Two")
    download.update!(content_hash: Digest::SHA256.file(archive).hexdigest, destination_path: EmberVault::Paths.relative(archive))
    perform_enqueued_jobs { KnowledgePackageInstaller.new(download).call }
    assert_equal 1, download.documents.count
    assert_equal first_id, download.documents.first.id
    assert_equal "Version Two", download.documents.first.title
  ensure
    File.delete(archive) if archive&.file?
  end

  test "failed update indexing restores the working installed version" do
    package_id = "failed-update-pack-#{SecureRandom.hex(4)}"
    archive = build_archive(package_id, "stable-article", "Working Version")
    download = package_download(package_id, archive)
    perform_enqueued_jobs { KnowledgePackageInstaller.new(download).call }
    installed_path = EmberVault::Paths.resolve(download.documents.first.stored_path)
    assert_includes installed_path.read, "Working Version"

    File.delete(archive)
    archive = EmberVault::Paths.content_for("knowledge-pack").join("#{package_id}.zip")
    Zip::File.open(archive, create: true) do |zip|
      zip.get_output_stream("guide/article.md") { |io| io.write("# Broken Update\n") }
      metadata = { id: "stable-article", slug: "guide", title: "Broken Update", category: "test", version: 2, content_hash: "d" * 64 }
      zip.get_output_stream("guide/metadata.json") { |io| io.write(metadata.to_json) }
    end
    download.update!(package_version: 2, content_hash: Digest::SHA256.file(archive).hexdigest,
      destination_path: EmberVault::Paths.relative(archive))
    clear_enqueued_jobs
    KnowledgePackageInstaller.new(download).call
    backup_path = enqueued_jobs.last.fetch(:args).last
    clear_enqueued_jobs
    assert_raises(StandardError) { KnowledgePackIndexJob.perform_now(download, backup_path) }
    assert_equal "Working Version", download.documents.first.reload.title
    assert_includes installed_path.read, "Working Version"
    assert_equal 1, download.reload.installed_package_version
  ensure
    File.delete(archive) if archive&.file?
  end

  private

  def build_archive(package_id, article_id, title)
    archive = EmberVault::Paths.content_for("knowledge-pack").join("#{package_id}.zip")
    FileUtils.mkdir_p(archive.dirname)
    Zip::File.open(archive, create: true) do |zip|
      zip.get_output_stream("guide/article.md") { |io| io.write("# #{title}\n\nUseful text.") }
      metadata = { id: article_id, slug: "guide", title:, category: "test", version: 1, content_hash: "c" * 64 }
      zip.get_output_stream("guide/metadata.json") { |io| io.write(metadata.to_json) }
    end
    archive
  end

  def package_download(package_id, archive, content_hash: Digest::SHA256.file(archive).hexdigest)
    ContentDownload.create!(resource_id: "knowledge-pack:#{package_id}", package_id:, package_version: 1, content_hash:,
      title: "Test Pack", source_url: "https://raw.githubusercontent.com/test.zip", kind: "knowledge-pack", status: "complete",
      destination_path: EmberVault::Paths.relative(archive))
  end
end
