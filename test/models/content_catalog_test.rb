require "test_helper"

class ContentCatalogTest < ActiveSupport::TestCase
  test "resolves wikipedia and inherited Kiwix tier resources" do
    catalog = ContentCatalog.new
    wikipedia = catalog.resolve([ "wikipedia:top-mini" ])
    assert_equal 1, wikipedia.length
    assert_equal "zim", wikipedia.first.fetch("kind")
    assert_match(/download\.kiwix\.org/, wikipedia.first.fetch("url"))

    category = catalog.categories.find { |item| item.fetch("tiers").any? { |tier| tier["includesTier"] } }
    tier = category.fetch("tiers").find { |item| item["includesTier"] }
    resources = catalog.resolve([ "tier:#{category.fetch('slug')}:#{tier.fetch('slug')}" ])
    assert resources.length > tier.fetch("resources").length
  end

  test "resolves every resource only once" do
    catalog = ContentCatalog.new
    resources = catalog.resolve([ "wikipedia:top-mini", "wikipedia:top-mini" ])
    assert_equal resources.map { |item| item.fetch("id") }.uniq, resources.map { |item| item.fetch("id") }
  end
end
