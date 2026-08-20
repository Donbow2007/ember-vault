require "json"
require "open3"

class MapIndexer
  SCRIPT = Rails.root.join("vendor", "map_indexer", "index.js")
  MODULES = Rails.root.join("vendor", "map_indexer", "node_modules")

  def initialize(download)
    @download = download
  end

  def call
    path = EmberVault::Paths.resolve(@download.destination_path)
    features = []
    Open3.popen3({ "NODE_PATH" => MODULES.to_s }, "node", SCRIPT.to_s, path.to_s) do |stdin, stdout, stderr, thread|
      stdin.close
      stdout.each_line { |line| features << JSON.parse(line, symbolize_names: true) }
      error = stderr.read
      raise "Map indexing failed: #{error.to_s.first(500)}" unless thread.value.success?
    end

    MapFeature.transaction do
      @download.map_features.delete_all
      now = Time.current
      features.each_slice(1_000) do |batch|
        @download.map_features.insert_all!(batch.map { |feature| feature.merge(created_at: now, updated_at: now) })
      end
    end
  end
end
