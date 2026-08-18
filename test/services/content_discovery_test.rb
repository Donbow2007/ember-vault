require "test_helper"

class ContentDiscoveryTest < ActiveSupport::TestCase
  test "finds bundled catalog resources and signs their install metadata" do
    result = ContentDiscovery.new.local("water treatment").find { |item| item.title == "Water Treatment Library" }

    assert result
    assert_equal "zim", result.kind
    assert_equal result.to_h, ContentDiscovery.verify(result.token).to_h
  end

  test "does not return an empty-topic catalog dump" do
    assert_empty ContentDiscovery.new.local(" ")
    assert_empty ContentDiscovery.new.remote(" ")
  end

  test "remote discovery returns public books and excludes papers and lending-only records" do
    discovery = ContentDiscovery.new
    discovery.define_singleton_method(:get_json) do |uri|
      if uri.host == "openlibrary.org"
        { "docs" => [
          { "key" => "/works/OL1W", "title" => "Water Handbook", "author_name" => [ "A. Guide" ],
            "first_publish_year" => 1910, "ia" => [ "water-handbook" ], "public_scan_b" => true, "ebook_access" => "public" },
          { "key" => "/works/OL2W", "title" => "Water Journal", "ia" => [ "paper" ], "public_scan_b" => true, "ebook_access" => "public" },
          { "key" => "/works/OL3W", "title" => "Borrowed Water Book", "ia" => [ "borrowed" ], "public_scan_b" => false, "ebook_access" => "borrowable" }
        ] }
      else
        { "files" => [ { "name" => "water-handbook_djvu.txt", "size" => "1200" } ] }
      end
    end

    results = discovery.remote("water")

    assert_equal [ "Water Handbook" ], results.map(&:title)
    assert_equal "Open Library / Internet Archive", results.first.source
    assert_equal "https://archive.org/download/water-handbook/water-handbook_djvu.txt", results.first.source_url
  end
end
