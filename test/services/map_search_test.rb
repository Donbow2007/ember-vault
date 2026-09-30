require "test_helper"

class MapSearchTest < ActiveSupport::TestCase
  setup do
    @pack = MapPack.create!(title: "Search Test", stored_path: "maps/search/test.pmtiles")
    @pack.map_features.create!(name: "Mountain Home", category: "places", kind: "city", latitude: 36.335, longitude: -92.385)
    @pack.map_features.create!(name: "Norfork Lake", category: "water", kind: "lake", latitude: 36.3, longitude: -92.25)
    @pack.map_features.create!(name: "Highway 5", category: "roads", kind: "major_road", latitude: 36.34, longitude: -92.38)
  end

  teardown { @pack.destroy! }

  test "finds a place name offline" do
    assert_equal "Mountain Home", MapSearch.new(@pack.map_features).call("Mountain Home").first.name
  end

  test "finds a fuzzy geographic name" do
    assert_equal "Norfork Lake", MapSearch.new(@pack.map_features).call("Norfork Lke").first.name
  end
end
