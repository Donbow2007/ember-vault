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
      zip.get_output_stream("bowline/metadata.json") { |io| io.write({ title: "Bowline" }.to_json) }
      zip.get_output_stream("clove-hitch/article.md") { |io| io.write("# Clove Hitch\n\n## Steps\n\n1. Cross the rope.") }
      zip.get_output_stream("clove-hitch/metadata.json") { |io| io.write({ title: "Clove Hitch" }.to_json) }
    end
    download = ContentDownload.create!(resource_id: "knowledge-pack:#{package_id}", package_id:, package_version: 1,
      content_hash: Digest::SHA256.file(archive).hexdigest, title: "Knots", source_url: "https://example.com/knots.zip",
      kind: "knowledge-pack", status: "complete", destination_path: EmberVault::Paths.relative(archive))

    assert_enqueued_with(job: KnowledgePackIndexJob, args: [ download ]) { KnowledgePackageInstaller.new(download).call }

    assert_equal 2, download.documents.count
    assert_equal [ "Bowline", "Clove Hitch" ], download.documents.order(:title).pluck(:title)
    assert download.documents.all? { |document| document.content_type == "text/markdown" }
  ensure
    File.delete(archive) if archive && archive.file?
  end
end
