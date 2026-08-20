require "json"

class ContentCatalog
  CATALOG_ROOT = Rails.root.join("config", "content_catalog")

  attr_reader :categories, :maps, :wikipedia

  def initialize
    @categories = read("kiwix-categories.json").fetch("categories")
    @maps = read("maps.json").fetch("collections")
    @wikipedia = read("wikipedia.json").fetch("options")
  end

  def resolve(keys)
    Array(keys).flat_map { |key| resolve_key(key) }.compact.uniq { |resource| resource.fetch("id") }
  end

  def installation_size_mb(keys)
    resolve(keys).sum { |resource| resource.fetch("size_mb", 0).to_i }
  end

  def searchable_resources
    resources = categories.flat_map { |category| category.fetch("tiers").flat_map { |tier| resolve_tier(category, tier) } }
    resources += maps.flat_map { |collection| collection.fetch("resources", []).map { |item| item.merge("kind" => "map") } }
    resources += wikipedia.filter_map { |item| item.merge("title" => item.fetch("name"), "kind" => "zim") if item["url"] }
    resources.uniq { |resource| resource.fetch("id") }
  end

  private

  def read(filename)
    JSON.parse(CATALOG_ROOT.join(filename).read)
  end

  def resolve_key(key)
    type, *parts = key.to_s.split(":")
    case type
    when "wikipedia"
      option = wikipedia.find { |item| item["id"] == parts.first }
      option && option["url"] ? [ option.merge("title" => option.fetch("name"), "kind" => "zim") ] : []
    when "map"
      maps.find { |item| item["slug"] == parts.first }&.fetch("resources", [])&.map { |item| item.merge("kind" => "map") } || []
    when "tier"
      category = categories.find { |item| item["slug"] == parts.first }
      tier = category&.fetch("tiers", [])&.find { |item| item["slug"] == parts.second }
      resolve_tier(category, tier)
    else
      []
    end
  end

  def resolve_tier(category, tier)
    return [] unless category && tier

    inherited = if tier["includesTier"]
      resolve_tier(category, category.fetch("tiers").find { |item| item["slug"] == tier["includesTier"] })
    else
      []
    end
    inherited + tier.fetch("resources", []).map { |item| item.merge("kind" => item["type"] || "zim") }
  end
end
