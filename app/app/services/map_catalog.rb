require "json"

class MapCatalog
  CATALOG_PATH = Rails.root.join("config", "map_catalog.json")

  Entry = Data.define(:id, :title, :description, :url, :version, :size_mb, :region)

  def self.entries
    JSON.parse(CATALOG_PATH.read).fetch("collections").flat_map do |collection|
      collection.fetch("resources", []).map do |item|
        Entry.new(
          id: item.fetch("id"),
          title: item.fetch("title").tr("_", " "),
          description: item["description"],
          url: item.fetch("url"),
          version: item.fetch("version"),
          size_mb: item["size_mb"].to_i,
          region: collection.fetch("slug")
        )
      end
    end
  end

  def self.find(id)
    entries.find { |entry| entry.id == id.to_s } || raise(ActiveRecord::RecordNotFound, "Unknown map region")
  end
end
