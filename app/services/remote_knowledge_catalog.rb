require "net/http"
require "json"

class RemoteKnowledgeCatalog
  CACHE_FILE = "knowledge-manifest.json"
  Result = Data.define(:manifest, :online, :error)

  def fetch(force: false)
    uri = manifest_uri
    return cached_result("Knowledge manifest URL is not configured") unless uri
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 4, read_timeout: 8) { |http| http.get(uri.request_uri) }
    raise "Manifest request returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    manifest = validate(JSON.parse(response.body)); absolutize_urls!(manifest, uri); FileUtils.mkdir_p(cache_path.dirname); cache_path.write(JSON.pretty_generate(manifest))
    Result.new(manifest:, online: true, error: nil)
  rescue => error
    cached_result(error.message)
  end

  def packages(result: fetch)
    result.manifest.fetch("categories", []).flat_map do |category|
      category.fetch("packages", []).map { |pack| pack.merge("category_name" => category["name"], "category_slug" => category["slug"]) }
    end
  end

  private
  def manifest_uri
    value = ENV["EMBER_VAULT_KNOWLEDGE_MANIFEST_URL"].to_s.strip
    URI(value) if value.present? && URI(value).is_a?(URI::HTTP)
  rescue URI::InvalidURIError
    nil
  end
  def cache_path = EmberVault::Paths.config.join(CACHE_FILE)
  def cached_result(error)
    manifest = cache_path.file? ? validate(JSON.parse(cache_path.read)) : { "schema_version" => 1, "categories" => [] }
    Result.new(manifest:, online: false, error:)
  rescue JSON::ParserError
    Result.new(manifest: { "schema_version" => 1, "categories" => [] }, online: false, error:)
  end
  def validate(manifest)
    raise "Unsupported knowledge manifest schema" unless manifest["schema_version"] == 1
    manifest.fetch("categories"); manifest
  end
  def absolutize_urls!(manifest, base)
    manifest.fetch("categories").each { |category| category.fetch("packages", []).each { |pack| pack["download_url"] = URI.join(base, pack.fetch("download_url")).to_s } }
  end
end
