require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "renders the command dashboard" do
    get root_url
    assert_response :success
    assert_select "h1", /When the signal/
    assert_select "form.search-console"
    assert_select "nav.primary-nav .module-nav-link", count: 0
    assert_select "nav.primary-nav", text: /Manuals/, count: 0
    assert_select ".metric", text: /DEVICE STORAGE.*USED.*FREE/m
    assert_select "form[action='#{theme_setting_path}'] button", text: "DARK"
    assert_select "form[action='#{theme_setting_path}'] button", text: "LIGHT"
    assert_select ".module-card", count: 0
    assert_select ".empty-archive", text: /NO MODULES DOWNLOADED/
  end

  test "only shows modules backed by local content" do
    Document.create!(title: "Local Guide", original_filename: "guide.txt", content_type: "text/plain",
      stored_path: "storage/archive_files/guide.txt", byte_size: 10, status: "ready", passage_count: 0)
    ContentDownload.create!(resource_id: "local-map", title: "Local Map", source_url: "https://example.test/map.pmtiles",
      kind: "map", status: "complete", destination_path: "storage/content/map/local-map.pmtiles")

    get root_url

    assert_select ".module-card", count: 2
    assert_select ".module-card", text: /The Archive/
    assert_select ".module-card", text: /World Atlas/
    assert_select ".module-card", text: /Medical/, count: 0
    assert_select ".module-card", text: /Learning/, count: 0
    assert_select ".module-card a[href='#{documents_path}']"
    assert_select ".module-card a[href='#{maps_path}']"
    assert_select "nav.primary-nav a.module-nav-link[href='#{documents_path}']", text: "The Archive"
    assert_select "nav.primary-nav a.module-nav-link[href='#{maps_path}']", text: "World Atlas"
  end

  test "accepts a local archive query" do
    document = Document.create!(title: "Water Guide", original_filename: "water.zim", content_type: "application/x-openzim",
      stored_path: "storage/content/zim/water.zim", byte_size: 10, status: "ready", passage_count: 1)
    passage = document.passages.create!(position: 0, heading: "Water Purification", body: "water purification methods")
    Passage.rebuild_search_index

    get search_url, params: { q: "water purification" }

    assert_response :success
    assert_select "turbo-frame#search_results", /water purification/
    assert_select "a[href='#{document_path(document, passage_id: passage.id, anchor: "passage-#{passage.id}")}']"
  end

  test "includes map features in normal search and links to the positioned map" do
    map = ContentDownload.create!(resource_id: "searchable-map", title: "Arkansas", source_url: "https://example.test/map.pmtiles",
      kind: "map", status: "complete", destination_path: "storage/content/map/arkansas.pmtiles")
    feature = map.map_features.create!(name: "Christenson Road", category: "roads", kind: "minor_road",
      latitude: 36.35234, longitude: -92.31228)

    get search_url, params: { q: "Christenson Road" }

    assert_response :success
    assert_select ".map-search-result", text: /Christenson Road/
    assert_select "a[href='#{map_path(map, feature_id: feature.id)}']"
    assert_select ".document-search-results", text: /No indexed article or document passage/
    assert_select ".map-search-results .map-search-result", text: /Christenson Road/
  end

  test "shows document results before separated map results" do
    document = Document.create!(title: "River Guide", original_filename: "river.txt", content_type: "text/plain",
      stored_path: "storage/archive_files/river.txt", byte_size: 10, status: "ready", passage_count: 1)
    document.passages.create!(position: 0, heading: "River Crossing", body: "river crossing safety")
    map = ContentDownload.create!(resource_id: "river-map", title: "Region", source_url: "https://example.test/map.pmtiles",
      kind: "map", status: "complete", destination_path: "storage/content/map/river.pmtiles")
    map.map_features.create!(name: "White River", category: "water", kind: "river", latitude: 36.2, longitude: -92.3)
    Passage.rebuild_search_index

    get search_url, params: { q: "river" }

    assert_response :success
    groups = css_select(".search-result-group")
    assert_equal %w[document-search-results map-search-results], groups.map { |group| group["class"].split.last }
    assert_select ".document-search-results", text: /River Crossing/
    assert_select ".map-search-results", text: /White River/
  end
end
