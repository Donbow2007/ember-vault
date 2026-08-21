require "test_helper"

class ContentCatalogTest < ActiveSupport::TestCase
  test "resolves wikipedia and inherited curated presets" do
    catalog = ContentCatalog.new
    wikipedia = catalog.resolve([ "wikipedia:top-mini" ])
    assert_equal 1, wikipedia.length
    assert_equal "zim", wikipedia.first.fetch("kind")
    assert_match(/download\.kiwix\.org/, wikipedia.first.fetch("url"))

    basic = catalog.resolve("preset:basic")
    suggested = catalog.resolve("preset:suggested")
    comprehensive = catalog.resolve("preset:comprehensive")
    assert_operator suggested.length, :>, basic.length
    assert_operator comprehensive.length, :>, suggested.length
    assert_empty basic.map { |item| item.fetch("id") } - suggested.map { |item| item.fetch("id") }
  end

  test "resolves every resource only once" do
    catalog = ContentCatalog.new
    resources = catalog.resolve([ "wikipedia:top-mini", "wikipedia:top-mini" ])
    assert_equal resources.map { |item| item.fetch("id") }.uniq, resources.map { |item| item.fetch("id") }
  end

  test "reports cumulative download and installation sizes for inherited presets" do
    catalog = ContentCatalog.new

    assert_equal 8, catalog.installation_size_mb("preset:basic")
    assert_equal 37, catalog.installation_size_mb("preset:suggested")
    assert_equal 134, catalog.installation_size_mb("preset:comprehensive")
    assert_operator catalog.installed_size_mb("preset:comprehensive"), :>, catalog.installation_size_mb("preset:comprehensive")
    assert_equal catalog.resolve("preset:basic").sum { |item| item.fetch("size_bytes") }, catalog.download_size_bytes("preset:basic")
  end

  test "exposes every state and DC while preserving individual map resources" do
    catalog = ContentCatalog.new

    assert_equal 51, catalog.map_jurisdictions.length
    assert_equal 50, catalog.map_jurisdictions.count { |place| place.fetch("available") }
    assert_not catalog.map_jurisdictions.find { |place| place.fetch("code") == "DC" }.fetch("available")

    arkansas = catalog.maps_for("AR").sole
    assert_equal "Arkansas", arkansas.fetch("admin1_name")
    assert_equal "statewide", arkansas.fetch("coverage_level")
    assert_equal "topographic", arkansas.fetch("map_type")
    assert_equal [ "arkansas" ], catalog.resolve("map-resource:arkansas").map { |resource| resource.fetch("id") }
  end

  test "keeps legacy regional map selections working" do
    resources = ContentCatalog.new.resolve("map:west-south-central")

    assert_includes resources.map { |resource| resource.fetch("id") }, "arkansas"
    assert_includes resources.map { |resource| resource.fetch("id") }, "texas"
  end

  test "keeps religious texts individually selectable and outside every practical tier" do
    catalog = ContentCatalog.new
    religious_ids = catalog.religion.map { |item| item.fetch("id") }

    assert_equal 6, religious_ids.length
    assert_equal religious_ids, religious_ids.uniq
    assert catalog.religion.all? { |item| item.fetch("redistribution_status") == "verified" }
    assert catalog.religion.all? { |item| item.key?("translation") && item.key?("language") && item.key?("license") }
    assert catalog.religion.all? { |item| item.fetch("sha256").match?(/\A[0-9a-f]{64}\z/) }

    tier_ids = catalog.presets.flat_map { |preset| catalog.resolve("preset:#{preset.fetch('id')}").map { |item| item.fetch("id") } }
    assert_empty tier_ids & religious_ids
    assert_equal [ religious_ids.first ], catalog.resolve("religion:#{religious_ids.first}").map { |item| item.fetch("id") }
    assert catalog.religion_candidates.all? { |candidate| candidate.fetch("status") == "human_review" }
  end

  test "all enabled practical packages carry auditable source and integrity metadata" do
    catalog = ContentCatalog.new

    assert_equal 23, catalog.packages.length
    catalog.packages.each do |package|
      assert_includes %w[primary-government historical-primary-source], package.fetch("trust_level")
      assert package.fetch("source_url").start_with?("https://")
      assert package.fetch("url").start_with?("https://")
      assert package.fetch("license").present?
      assert package.fetch("redistribution_status").start_with?("verified")
      assert package.fetch("sha256").match?(/\A[0-9a-f]{64}\z/)
      assert package.fetch("categories").any?
    end
    assert catalog.knowledge_candidates.any? { |candidate| candidate.fetch("category") == "gardening-agriculture" }
  end

  test "separates current herbal safety guidance from historical claims" do
    catalog = ContentCatalog.new
    herbal = catalog.packages_for("herbal-medicine")

    assert_equal 3, herbal.length
    assert_includes catalog.resolve("preset:suggested").map { |item| item.fetch("id") }, "nih-botanical-supplements-background"
    assert_empty catalog.resolve("preset:basic").map { |item| item.fetch("id") } & herbal.map { |item| item.fetch("id") }
    assert_equal 2, herbal.count { |item| item["historical"] }
    assert herbal.all? { |item| item.dig("safety_metadata", "natural_is_safe") == false }
    assert herbal.select { |item| item["historical"] }.all? { |item| item.fetch("evidence_scope").match?(/Historical/i) }
  end
end
