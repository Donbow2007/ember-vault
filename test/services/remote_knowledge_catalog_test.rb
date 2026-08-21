require "test_helper"

class RemoteKnowledgeCatalogTest < ActiveSupport::TestCase
  def valid_manifest
    { schema_version: 1, categories: [ { id: "cat-1", name: "Water", slug: "water", packages: [
      { id: "pack-1", name: "Purification", slug: "purification", version: 2, content_hash: "a" * 64,
        download_url: "packs/water/purification.zip", download_size: 123 }
    ] } ] }
  end

  test "fetches and caches a valid manifest while resolving relative URLs" do
    Dir.mktmpdir do |dir|
      catalog = RemoteKnowledgeCatalog.new
      catalog.define_singleton_method(:cache_path) { Pathname(dir).join("manifest.json") }
      response = Net::HTTPOK.new("1.1", "200", "OK")
      response.instance_variable_set(:@read, true)
      response.body = valid_manifest.to_json
      catalog.define_singleton_method(:request) { |uri, _redirects = 0| [ response, uri ] }
      result = catalog.fetch
      assert result.online, result.error
      assert_equal "https://raw.githubusercontent.com/Donbow2007/ember-vault-public-library/main/packs/water/purification.zip", catalog.packages(result:).first["download_url"]
      assert Pathname(dir).join("manifest.json").file?
    end
  end

  test "rejects unsupported schemas and malformed JSON without writing cache" do
    [ { schema_version: 2, categories: [] }.to_json, "{" ].each do |body|
      Dir.mktmpdir do |dir|
        catalog = RemoteKnowledgeCatalog.new
        cache = Pathname(dir).join("manifest.json")
        catalog.define_singleton_method(:cache_path) { cache }
        response = Net::HTTPOK.new("1.1", "200", "OK")
        response.instance_variable_set(:@read, true)
        response.body = body
        catalog.define_singleton_method(:request) { |uri, _redirects = 0| [ response, uri ] }
        result = catalog.fetch
        assert_not result.online
        assert_not cache.exist?
      end
    end
  end

  test "handles a missing first manifest and rejects unsafe URLs" do
    catalog = RemoteKnowledgeCatalog.new
    response = Net::HTTPNotFound.new("1.1", "404", "Not Found")
    catalog.define_singleton_method(:request) { |uri, _redirects = 0| [ response, uri ] }
    result = catalog.fetch
    assert_not result.online
    assert_match(/not been published/, result.error)
    assert_raises(RuntimeError) { catalog.send(:validate_uri!, URI("http://example.com/manifest.json")) }
    assert_raises(RuntimeError) { catalog.send(:validate_uri!, URI("https://example.com/manifest.json")) }
  end

  test "returns cached manifest without deleting installed state when offline" do
    Dir.mktmpdir do |dir|
      cache = Pathname(dir).join("manifest.json")
      cache.write({ schema_version: 1, categories: [ { id: "cat-1", name: "Water", slug: "water", packages: [
        { id: "pack-1", name: "Purification", slug: "purification", version: 2, content_hash: "a" * 64,
          download_url: "packs/water.zip" }
      ] } ] }.to_json)
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
