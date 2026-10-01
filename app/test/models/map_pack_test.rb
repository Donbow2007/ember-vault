require "test_helper"

class MapPackTest < ActiveSupport::TestCase
  test "pack path stays inside portable maps storage" do
    pack = MapPack.new(title: "Test", stored_path: "maps/test/test.pmtiles")
    assert_equal EmberVault::PortableStorage.path("maps", "test", "test.pmtiles").expand_path, pack.pack_path
  end

  test "rejects paths outside map storage" do
    pack = MapPack.new(title: "Bad", stored_path: "../outside.pmtiles")
    assert_raises(ArgumentError) { pack.pack_path }
  end
end
