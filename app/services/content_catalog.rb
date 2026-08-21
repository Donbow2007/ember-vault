require "json"

class ContentCatalog
  CATALOG_ROOT = Rails.root.join("config", "content_catalog")
  US_JURISDICTIONS = [
    %w[AL Alabama], %w[AK Alaska], %w[AZ Arizona], %w[AR Arkansas], %w[CA California], %w[CO Colorado],
    %w[CT Connecticut], %w[DE Delaware], [ "DC", "District of Columbia" ], %w[FL Florida], %w[GA Georgia],
    %w[HI Hawaii], %w[ID Idaho], %w[IL Illinois], %w[IN Indiana], %w[IA Iowa], %w[KS Kansas], %w[KY Kentucky],
    %w[LA Louisiana], %w[ME Maine], %w[MD Maryland], [ "MA", "Massachusetts" ], %w[MI Michigan],
    %w[MN Minnesota], %w[MS Mississippi], %w[MO Missouri], %w[MT Montana], %w[NE Nebraska], %w[NV Nevada],
    [ "NH", "New Hampshire" ], [ "NJ", "New Jersey" ], [ "NM", "New Mexico" ], [ "NY", "New York" ],
    [ "NC", "North Carolina" ], [ "ND", "North Dakota" ], %w[OH Ohio], %w[OK Oklahoma], %w[OR Oregon],
    %w[PA Pennsylvania], [ "RI", "Rhode Island" ], [ "SC", "South Carolina" ], [ "SD", "South Dakota" ],
    %w[TN Tennessee], %w[TX Texas], %w[UT Utah], %w[VT Vermont], %w[VA Virginia], %w[WA Washington],
    [ "WV", "West Virginia" ], %w[WI Wisconsin], %w[WY Wyoming]
  ].map { |code, name| { "code" => code, "name" => name, "type" => code == "DC" ? "district" : "state" } }.freeze

  attr_reader :categories, :knowledge_candidates, :maps, :packages, :presets, :religion, :religion_candidates, :wikipedia

  def initialize
    knowledge = read("knowledge.json")
    @categories = knowledge.fetch("categories")
    @packages = knowledge.fetch("packages").select { |item| item.fetch("enabled", false) }
    @presets = knowledge.fetch("presets")
    @knowledge_candidates = knowledge.fetch("research_candidates")
    @maps = read("maps.json").fetch("collections")
    religion_manifest = read("religion.json")
    @religion = religion_manifest.fetch("items")
    @religion_candidates = religion_manifest.fetch("research_candidates")
    @wikipedia = read("wikipedia.json").fetch("options")
  end

  def resolve(keys)
    Array(keys).flat_map { |key| resolve_key(key) }.compact.uniq { |resource| resource.fetch("id") }
  end

  def installation_size_mb(keys)
    resolve(keys).sum { |resource| resource.fetch("size_mb", 0).to_i }
  end

  def download_size_bytes(keys)
    resolve(keys).sum { |resource| resource.fetch("size_bytes", resource.fetch("size_mb", 0).to_i.megabytes).to_i }
  end

  def installed_size_mb(keys)
    resolve(keys).sum { |resource| resource.fetch("installed_size_mb", resource.fetch("size_mb", 0)).to_i }
  end

  def resource(resource_id)
    searchable_resources.find { |item| item["id"] == resource_id }
  end

  def searchable_resources
    resources = packages.map { |item| item.merge("kind" => "document", "source" => item.fetch("organization")) }
    resources += map_resources
    resources += religion.map { |item| item.merge("kind" => "document", "description" => religion_description(item)) }
    resources += wikipedia.filter_map { |item| item.merge("title" => item.fetch("name"), "kind" => "zim") if item["url"] }
    resources.uniq { |resource| resource.fetch("id") }
  end

  def packages_for(category_slug)
    packages.select { |item| item.fetch("primary_category") == category_slug }
  end

  def map_resources
    maps.flat_map do |collection|
      collection.fetch("resources", []).map do |item|
        jurisdiction = jurisdiction_for(item)
        item.merge("kind" => "map", "source" => "Project NOMAD Maps", "license" => "Open map data",
          "country_code" => "US", "admin1_code" => jurisdiction&.fetch("code"),
          "admin1_name" => jurisdiction&.fetch("name") || item.fetch("title").tr("_", " "),
          "coverage_level" => "statewide", "map_type" => "topographic", "region" => collection.fetch("name"))
      end
    end
  end

  def map_jurisdictions
    available = map_resources.index_by { |resource| resource.fetch("admin1_name") }
    US_JURISDICTIONS.map { |place| place.merge("available" => available.key?(place.fetch("name"))) }
  end

  def maps_for(jurisdiction)
    query = jurisdiction.to_s.downcase.tr("_", " ")
    map_resources.select do |resource|
      [ resource["admin1_code"], resource["admin1_name"] ].compact.any? { |value| value.downcase == query }
    end
  end

  private

  def read(filename)
    JSON.parse(CATALOG_ROOT.join(filename).read)
  end

  def resolve_key(key)
    type, *parts = key.to_s.split(":")
    case type
    when "preset"
      resolve_preset(parts.first)
    when "package"
      item = packages.find { |candidate| candidate["id"] == parts.join(":") }
      item ? [ item.merge("kind" => "document") ] : []
    when "wikipedia"
      option = wikipedia.find { |item| item["id"] == parts.first }
      option && option["url"] ? [ option.merge("title" => option.fetch("name"), "kind" => "zim") ] : []
    when "map"
      maps.find { |item| item["slug"] == parts.first }&.fetch("resources", [])&.map { |item| item.merge("kind" => "map") } || []
    when "map-resource"
      resource = map_resources.find { |item| item["id"] == parts.first }
      resource ? [ resource ] : []
    when "religion"
      item = religion.find { |candidate| candidate["id"] == parts.join(":") }
      item ? [ item.merge("kind" => "document") ] : []
    else
      []
    end
  end

  def resolve_preset(id)
    preset = presets.find { |item| item["id"] == id }
    return [] unless preset

    inherited = preset["includes"] ? resolve_preset(preset.fetch("includes")) : []
    selected = preset.fetch("package_ids").filter_map { |resource_id| packages.find { |item| item["id"] == resource_id } }
    (inherited + selected).map { |item| item.merge("kind" => "document") }
  end

  def jurisdiction_for(resource)
    normalized = resource.fetch("title").tr("_", " ")
    US_JURISDICTIONS.find { |place| place.fetch("name").casecmp?(normalized) }
  end

  def religion_description(item)
    [ item["tradition"], item["work"], item["translation"], item["language"] ].compact.join(" · ")
  end
end
