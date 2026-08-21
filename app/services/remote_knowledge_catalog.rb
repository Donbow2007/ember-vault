require "net/http"
require "json"

class RemoteKnowledgeCatalog
  DEFAULT_MANIFEST_URL = "https://raw.githubusercontent.com/Donbow2007/ember-vault-public-library/main/manifest.json"
  CACHE_FILE = "knowledge-manifest.json"
  ALLOWED_HOSTS = %w[raw.githubusercontent.com github.com].freeze
  MAX_REDIRECTS = 3
  Result = Data.define(:manifest, :online, :error)

  def fetch(force: false)
    uri = manifest_uri
    response, final_uri = request(uri)
    raise "The public knowledge catalog has not been published yet" if response.is_a?(Net::HTTPNotFound)
    raise "Knowledge catalog request returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    manifest = validate(JSON.parse(response.body))
    absolutize_urls!(manifest, final_uri)
    FileUtils.mkdir_p(cache_path.dirname)
    temporary_cache = cache_path.sub_ext(".tmp")
    temporary_cache.write(JSON.pretty_generate(manifest))
    File.rename(temporary_cache, cache_path)
    Result.new(manifest:, online: true, error: nil)
  rescue JSON::ParserError
    cached_result("The public knowledge catalog returned invalid JSON")
  rescue StandardError => error
    cached_result(error.message)
  end

  def packages(result: fetch)
    result.manifest.fetch("categories", []).flat_map do |category|
      category.fetch("packages", []).map { |pack| pack.merge("category_name" => category["name"], "category_slug" => category["slug"]) }
    end
  end

  private
  def manifest_uri
    uri = URI(ENV.fetch("EMBER_VAULT_KNOWLEDGE_MANIFEST_URL", DEFAULT_MANIFEST_URL))
    validate_uri!(uri, allow_configured_host: true)
    uri
  rescue URI::InvalidURIError => error
    raise "Invalid knowledge manifest URL: #{error.message}"
  end
  def cache_path = EmberVault::Paths.config.join(CACHE_FILE)
  def cached_result(error)
    manifest = cache_path.file? ? validate(JSON.parse(cache_path.read)) : { "schema_version" => 1, "categories" => [] }
    Result.new(manifest:, online: false, error:)
  rescue StandardError
    Result.new(manifest: { "schema_version" => 1, "categories" => [] }, online: false, error:)
  end
  def validate(manifest)
    raise "Knowledge manifest must be an object" unless manifest.is_a?(Hash)
    raise "Unsupported knowledge manifest schema" unless manifest["schema_version"] == 1
    categories = manifest.fetch("categories")
    raise "Knowledge manifest categories must be an array" unless categories.is_a?(Array)
    categories.each do |category|
      raise "Invalid knowledge category" unless category.is_a?(Hash) && category["id"].is_a?(String) && category["name"].is_a?(String) && category["slug"].is_a?(String)
      packages = category.fetch("packages")
      raise "Knowledge category packages must be an array" unless packages.is_a?(Array)
      packages.each { |pack| validate_package!(pack) }
    end
    manifest
  end
  def absolutize_urls!(manifest, base)
    manifest.fetch("categories").each do |category|
      category.fetch("packages").each do |pack|
        uri = URI.join(base, pack.fetch("download_url"))
        validate_uri!(uri)
        pack["download_url"] = uri.to_s
      end
    end
  end

  def validate_package!(pack)
    required = %w[id name slug version content_hash download_url]
    raise "Invalid knowledge package" unless pack.is_a?(Hash) && required.all? { |key| pack[key].present? }
    raise "Invalid knowledge package version" unless pack["version"].is_a?(Integer) && pack["version"].positive?
    raise "Invalid knowledge package checksum" unless pack["content_hash"].is_a?(String) && pack["content_hash"].match?(/\A[0-9a-f]{64}\z/i)
    if pack.key?("download_size")
      raise "Invalid knowledge package size" unless pack["download_size"].is_a?(Integer) && pack["download_size"] >= 0
    end
  end

  def request(uri, redirects = 0)
    raise "Too many knowledge catalog redirects" if redirects > MAX_REDIRECTS
    validate_uri!(uri, allow_configured_host: redirects.zero?)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 4, read_timeout: 8) { |http| http.get(uri.request_uri) }
    if response.is_a?(Net::HTTPRedirection)
      location = response["location"]
      raise "Knowledge catalog redirect had no destination" if location.blank?
      return request(URI.join(uri, location), redirects + 1)
    end
    [ response, uri ]
  end

  def validate_uri!(uri, allow_configured_host: false)
    raise "Knowledge catalog URLs require HTTPS" unless uri.is_a?(URI::HTTPS) && uri.port == 443
    configured_host = URI(ENV.fetch("EMBER_VAULT_KNOWLEDGE_MANIFEST_URL", DEFAULT_MANIFEST_URL)).host rescue nil
    allowed = ALLOWED_HOSTS.include?(uri.host) || uri.host == configured_host
    raise "Unapproved knowledge catalog host" unless allowed
  end
end
