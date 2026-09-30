require "json"
require "open3"

class MapIndexer
  SCRIPT = Rails.root.join("vendor", "map_indexer", "index.js")
  MODULES = Rails.root.join("vendor", "map_indexer", "node_modules")

  def initialize(map_pack)
    @map_pack = map_pack
  end

  def call
    root = Pathname.new(ENV.fetch("EMBER_VAULT_DATA_DIR", Rails.root.join("storage").to_s)).expand_path
    stored = Pathname.new(@map_pack.stored_path)
    path = (stored.absolute? ? stored : root.join(stored)).cleanpath
    features = []
    Open3.popen3({ "NODE_PATH" => MODULES.to_s }, "node", SCRIPT.to_s, path.to_s) do |stdin, stdout, stderr, thread|
      stdin.close
      stdout.each_line { |line| features << JSON.parse(line, symbolize_names: true) }
      error = stderr.read
      raise "Map indexing failed: #{error.to_s.first(500)}" unless thread.value.success?
    end

    MapFeature.transaction do
      @map_pack.map_features.delete_all
      now = Time.current
      features.each_slice(1_000) do |batch|
        @map_pack.map_features.insert_all!(batch.map { |feature| feature.merge(created_at: now, updated_at: now) })
      end
    end
  end
end
