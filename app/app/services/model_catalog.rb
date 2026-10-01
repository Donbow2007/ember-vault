require "yaml"

class ModelCatalog
  Entry = Data.define(:id, :display_name, :filename, :repository, :upstream_filename, :download_url, :sha256, :license, :status, :runtime)

  def self.entries
    @entries ||= YAML.safe_load_file(Rails.root.join("config/model_catalog.yml")).fetch("models").map do |id, attributes|
      Entry.new(
        id:,
        display_name: attributes.fetch("display_name"),
        filename: attributes.fetch("filename"),
        repository: attributes["repository"],
        upstream_filename: attributes["upstream_filename"],
        download_url: attributes["download_url"],
        sha256: attributes["sha256"],
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

  def self.active
    selected = File.read(active_model_path).strip
    installed.find { |entry| entry.id == selected } || installed.first
  rescue Errno::ENOENT
    installed.first
  end

  def self.select!(id)
    entry = find(id)
    raise ArgumentError, "Unknown model." unless entry
    raise ArgumentError, "Model is not installed." unless model_path(entry).file?

    EmberVault::PortableStorage.prepare!
    File.write(active_model_path, entry.id)
    entry
  end

  def self.active_model_path
    EmberVault::PortableStorage.path("settings", "active-model")
  end

  def self.default
    active || entries.find { |entry| entry.status == "default" } || entries.first
  end

  def self.model_path(entry)
    EmberVault::PortableStorage.path("models", entry.filename)
  end
end
