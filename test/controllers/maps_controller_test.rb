require "test_helper"

class MapsControllerTest < ActionDispatch::IntegrationTest
  setup do
    filename = "test-map-#{Process.pid}.pmtiles"
    @download = ContentDownload.create!(resource_id: "test-map", title: "Test Region",
      source_url: "https://github.com/test.pmtiles", kind: "map", status: "complete",
      destination_path: "storage/content/map/#{filename}", downloaded_bytes: 16)
    @path = Rails.root.join(@download.destination_path)
    FileUtils.mkdir_p(@path.dirname)
    File.binwrite(@path, "0123456789abcdef")
  end

  teardown do
    File.delete(@path) if File.file?(@path)
  end

  test "lists and opens completed offline maps" do
    @download.map_features.create!(name: "Test Town", category: "places", kind: "locality",
      latitude: 34.7, longitude: -92.3)

    get maps_url
    assert_response :success
    assert_select "a[href='#{map_path(@download)}']", text: /Test Region/
    assert_select ".atlas-region-card", text: /1 INDEXED NAME/

    get map_url(@download)
    assert_response :success
    assert_select "[data-controller='atlas'][data-atlas-url-value='#{archive_map_path(@download)}']"
    assert_select "[data-atlas-search-url-value='#{search_map_path(@download)}']"
    assert_select "script[src*='maplibre-gl']"
    assert_select "script[src*='pmtiles']"
    assert_select "button.atlas-locate-button[data-action='click->atlas#locateDevice']", text: /LOCATE ME/
    assert File.file?(Rails.root.join("public/map_fonts/Noto Sans Regular/0-255.pbf"))
  end

  test "queues geographic reindexing from the archive" do
    assert_enqueued_with(job: MapIndexJob, args: [ @download ]) do
      post reindex_map_url(@download)
    end

    assert_redirected_to documents_url
  end

  test "opens a selected search feature centered on the offline map" do
    feature = @download.map_features.create!(name: "Selected Road", category: "roads", kind: "minor_road",
      latitude: 36.25, longitude: -92.35)

    get map_url(@download, feature_id: feature.id)

    assert_response :success
    assert_select "[data-atlas-initial-latitude-value='36.25'][data-atlas-initial-longitude-value='-92.35']"
    assert_select ".atlas-results", text: /Selected Road/
  end

  test "serves a local map archive with byte range support" do
    get archive_map_url(@download), headers: { "Range" => "bytes=0-6" }

    assert_response :partial_content
    assert_equal "bytes", response.headers["Accept-Ranges"]
    assert_equal "0123456", response.body
  end

  test "searches the persistent local geographic name index" do
    @download.map_features.create!(name: "Little Rock", category: "places", kind: "locality",
      latitude: 34.7465, longitude: -92.2896)

    get search_map_url(@download), params: { q: "little rock" }, as: :json

    assert_response :success
    result = response.parsed_body.first
    assert_equal "Little Rock", result.fetch("name")
    assert_equal "places", result.fetch("category")
    assert_in_delta 34.7465, result.fetch("latitude")
  end

  test "finds a road from a partial address with a misspelling" do
    @download.map_features.create!(name: "Christenson Road", category: "roads", kind: "minor_road",
      latitude: 36.25, longitude: -92.35)
    @download.map_features.create!(name: "Mountain Home", category: "places", kind: "locality",
      latitude: 36.34, longitude: -92.38)

    get search_map_url(@download), params: { q: "1850 christensen rd mountain home ar" }, as: :json

    assert_response :success
    assert_equal "Christenson Road", response.parsed_body.first.fetch("name")
  end
end
