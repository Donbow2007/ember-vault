require "net/http"
require "uri"
require "resolv"
require "ipaddr"
require "fileutils"
require "json"

class MapInstaller
  MAX_REDIRECTS = 5
  ALLOWED_HOSTS = %w[github.com raw.githubusercontent.com objects.githubusercontent.com].freeze
  BLOCKED_NETWORKS = %w[
    0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12
    192.0.0.0/24 192.0.2.0/24 192.168.0.0/16 198.18.0.0/15 198.51.100.0/24
    203.0.113.0/24 224.0.0.0/4 240.0.0.0/4 ::/128 ::1/128 fc00::/7 fe80::/10 ff00::/8 2001:db8::/32
  ].map { |network| IPAddr.new(network) }.freeze

  def initialize(map_pack, resolver: Resolv.method(:getaddresses))
    @map_pack = map_pack
    @resolver = resolver
  end

  def call
    @map_pack.update!(status: "downloading", error_message: nil, downloaded_bytes: 0)
    directory = EmberVault::PortableStorage.path("maps", @map_pack.catalog_id)
    FileUtils.mkdir_p(directory)
    destination = directory.join("#{@map_pack.catalog_id}.pmtiles")
    temporary = Pathname.new("#{destination}.part")
    download(URI.parse(@map_pack.source_url), temporary, initial: true)
    File.rename(temporary, destination)

    manifest = {
      format: "ember-map-pack", version: "1", title: @map_pack.title,
      region: @map_pack.catalog_id, pmtiles: destination.basename.to_s
    }
    File.write(directory.join("map-pack.json"), JSON.pretty_generate(manifest))

    relative = destination.relative_path_from(EmberVault::PortableStorage.root).to_s
    @map_pack.update!(stored_path: relative, byte_size: destination.size,
      downloaded_bytes: destination.size, status: "complete", version: @map_pack.catalog_version)
    MapIndexJob.perform_later(@map_pack)
  rescue StandardError => error
    FileUtils.rm_f(temporary) if defined?(temporary)
    @map_pack.update(status: "failed", error_message: error.message.to_s.first(500))
    raise if error.is_a?(Net::OpenTimeout) || error.is_a?(Net::ReadTimeout)
  end

  private

  def download(uri, destination, redirects = 0, initial: false)
    raise "Too many redirects" if redirects > MAX_REDIRECTS
    validate_uri!(uri, initial:)

    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 120) do |http|
      request = Net::HTTP::Get.new(uri.request_uri)
      http.request(request) do |response|
        if response.is_a?(Net::HTTPRedirection)
          location = response["location"]
          raise "Map redirect did not include a destination" if location.blank?
          return download(URI.join(uri, location), destination, redirects + 1)
        end
        raise "Map download failed with HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        bytes = 0
        File.open(destination, "wb") do |file|
          response.read_body do |chunk|
            file.write(chunk)
            bytes += chunk.bytesize
            if (bytes % 1.megabyte) < chunk.bytesize
              @map_pack.update_columns(downloaded_bytes: bytes, updated_at: Time.current)
            end
          end
        end
        @map_pack.update_columns(downloaded_bytes: bytes, updated_at: Time.current)
      end
    end
  end

  def validate_uri!(uri, initial: false)
    raise "Map downloads require HTTPS" unless uri.is_a?(URI::HTTPS) && uri.port == 443
    raise "Unapproved map host" if initial && !ALLOWED_HOSTS.include?(uri.host)
    raise "Unapproved redirect host" if uri.host.blank? || uri.host == "localhost" || uri.host.end_with?(".local")

    addresses = @resolver.call(uri.host)
    raise "Map host did not resolve" if addresses.empty?
    raise "Map host resolved to a private address" unless addresses.all? { |value| public_address?(IPAddr.new(value)) }
  end

  def public_address?(address)
    BLOCKED_NETWORKS.none? { |network| network.include?(address) }
  end
end
