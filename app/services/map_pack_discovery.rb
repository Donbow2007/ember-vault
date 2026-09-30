require "json"

class MapPackDiscovery
  MANIFEST = "map-pack.json"

  def call
    EmberVault::PortableStorage.prepare!
    discovered = Dir.glob(EmberVault::PortableStorage.path("maps", "*", MANIFEST)).filter_map { |path| discover(Pathname.new(path)) }
    MapPack.where.not(id: discovered).destroy_all
    discovered
  end

  private

  def discover(manifest_path)
    metadata = JSON.parse(manifest_path.read)
    pmtiles = manifest_path.dirname.join(metadata.fetch("pmtiles"))
    return unless pmtiles.file?

    relative = pmtiles.relative_path_from(EmberVault::PortableStorage.root).to_s
    pack = MapPack.find_or_initialize_by(stored_path: relative)
    pack.update!(
      title: metadata.fetch("title"),
      byte_size: pmtiles.size,
      format: "pmtiles",
      region: metadata["region"],
      version: metadata["version"]
    )
    pack.id
  rescue JSON::ParserError, KeyError => error
    Rails.logger.warn("Ignoring invalid map pack #{manifest_path}: #{error.message}")
    nil
  end
end
