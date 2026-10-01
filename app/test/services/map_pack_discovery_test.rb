require "test_helper"
require "fileutils"
require "json"

class MapPackDiscoveryTest < ActiveSupport::TestCase
  test "discovers a copied version one map pack" do
    directory = EmberVault::PortableStorage.path("maps", "discovery-test")
    FileUtils.mkdir_p(directory)
    pmtiles = directory.join("test.pmtiles")
    pmtiles.binwrite("PMTiles test fixture")
    directory.join("map-pack.json").write(JSON.generate(format: "ember-map-pack", version: "1", title: "Test Region", region: "TEST", pmtiles: "test.pmtiles"))

    assert_difference("MapPack.count", 1) { MapPackDiscovery.new.call }
    pack = MapPack.find_by!(title: "Test Region")
    assert_equal "TEST", pack.region
    assert_equal pmtiles.size, pack.byte_size
  ensure
    MapPack.where(title: "Test Region").destroy_all
    FileUtils.rm_rf(directory) if directory
  end
end
