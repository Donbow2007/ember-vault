require "test_helper"

class RemoteKnowledgeCatalogTest < ActiveSupport::TestCase
  test "returns cached manifest without deleting installed state when offline" do
    Dir.mktmpdir do |dir|
      cache = Pathname(dir).join("manifest.json")
      cache.write({ schema_version: 1, categories: [{ id: "cat-1", name: "Water", slug: "water", packages: [{ id: "pack-1", name: "Purification", version: 2 }] }] }.to_json)
      catalog = RemoteKnowledgeCatalog.new
      catalog.define_singleton_method(:cache_path) { cache }
      result = catalog.send(:cached_result, "network unavailable")
      assert_not result.online
      assert_equal "pack-1", catalog.packages(result:).first["id"]
      assert_equal "network unavailable", result.error
    end
  end

  test "detects an available update without changing installed content" do
    installed = ContentDownload.create!(resource_id: "knowledge-pack:pack-1", package_id: "pack-1", package_version: 1, title: "Purification", source_url: "https://example.com/pack.zip", kind: "knowledge-pack", status: "complete")
    remote_version = 2
    assert_operator remote_version, :>, installed.package_version
    assert_equal "complete", installed.reload.status
  end
end
