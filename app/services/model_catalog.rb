require "yaml"

class ModelCatalog
  Entry = Data.define(:id, :display_name, :filename, :repository, :upstream_filename, :license, :status, :runtime)

  def self.entries
    @entries ||= YAML.safe_load_file(Rails.root.join("config/model_catalog.yml")).fetch("models").map do |id, attributes|
      Entry.new(
        id:,
        display_name: attributes.fetch("display_name"),
        filename: attributes.fetch("filename"),
        repository: attributes["repository"],
        upstream_filename: attributes["upstream_filename"],
        license: attributes["license"],
        status: attributes.fetch("status"),
        runtime: attributes.fetch("runtime", {})
      )
    end
  end

  def self.find(id)
    entries.find { |entry| entry.id == id.to_s }
  end

  def self.installed
    entries.select { |entry| model_path(entry).file? }
  end

  def self.model_path(entry)
    EmberVault::PortableStorage.path("models", entry.filename)
  end
end
