require "json"

class MapPackDiscovery
  MANIFEST = "map-pack.json"

  def call
    EmberVault::PortableStorage.prepare!
    Dir.glob(EmberVault::PortableStorage.path("maps", "*", MANIFEST)).filter_map { |path| discover(Pathname.new(path)) }
  end

  private

  def discover(manifest_path)
    metadata = JSON.parse(manifest_path.read)
    raise KeyError, "unsupported map pack format" unless metadata.fetch("format", "ember-map-pack") == "ember-map-pack"
    raise KeyError, "unsupported map pack version" unless metadata.fetch("version").to_s == "1"

    pmtiles = manifest_path.dirname.join(metadata.fetch("pmtiles")).expand_path
    pack_root = manifest_path.dirname.expand_path
    raise KeyError, "PMTiles path escapes its pack directory" unless pmtiles.to_s.start_with?("#{pack_root}#{File::SEPARATOR}")
    return unless pmtiles.file?

    relative = pmtiles.relative_path_from(EmberVault::PortableStorage.root.expand_path).to_s
    pack = MapPack.find_or_initialize_by(stored_path: relative)
    pack.update!(
      title: metadata.fetch("title"),
      byte_size: pmtiles.size,
      format: "pmtiles",
      region: metadata["region"],
      version: metadata.fetch("version").to_s,
      catalog_id: catalog_id_for(metadata),
      status: "complete",
      downloaded_bytes: pmtiles.size
    )
    pack
  def catalog_id_for(metadata)
    id = metadata["region"].to_s
    MapCatalog.entries.any? { |entry| entry.id == id } ? id : nil
  end

  rescue JSON::ParserError, KeyError, ArgumentError => error
    Rails.logger.warn("Ignoring invalid map pack #{manifest_path}: #{error.message}")
    nil
  end
end
