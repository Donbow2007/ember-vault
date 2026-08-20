require "net/http"
require "uri"
require "resolv"
require "ipaddr"

class ContentFetcher
  class TransferCancelled < StandardError
    attr_reader :action

    def initialize(action)
      @action = action
      super("Transfer #{action}")
    end
  end

  ALLOWED_HOSTS = %w[download.kiwix.org archive.download.kiwix.org github.com raw.githubusercontent.com archive.org www.ncbi.nlm.nih.gov huggingface.co].freeze
  MAX_REDIRECTS = 5
  BLOCKED_NETWORKS = %w[
    0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12
    192.0.0.0/24 192.0.2.0/24 192.168.0.0/16 198.18.0.0/15 198.51.100.0/24
    203.0.113.0/24 224.0.0.0/4 240.0.0.0/4 ::/128 ::1/128 fc00::/7 fe80::/10 ff00::/8 2001:db8::/32
  ].map { |network| IPAddr.new(network) }.freeze

  def initialize(download, resolver: Resolv.method(:getaddresses))
    @download = download
    @resolver = resolver
  end

  def call
    handle_control_request!
    @download.update!(status: "downloading", error_message: nil)
    destination = destination_path
    FileUtils.mkdir_p(destination.dirname)
    @temporary_path = destination.sub_ext("#{destination.extname}.part")
    fetch(URI.parse(@download.source_url), @temporary_path, initial: true)
    handle_control_request!
    @download.update!(status: "complete", destination_path: EmberVault::Paths.relative(destination))
    @download.enqueue_indexing!
    @download.enqueue_map_indexing!
  rescue TransferCancelled => error
    handle_cancellation(error.action)
  rescue StandardError => error
    @download.update(status: "failed", error_message: error.message.to_s.first(500)) if @download.persisted?
    raise if error.is_a?(Net::OpenTimeout) || error.is_a?(Net::ReadTimeout)
  end

  private

  def fetch(uri, temporary_path, redirects = 0, initial: false)
    raise "Too many redirects" if redirects > MAX_REDIRECTS
    validate_uri!(uri, initial:)

    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 60) do |http|
      http.request_get(uri.request_uri) do |response|
        if response.is_a?(Net::HTTPRedirection)
          location = response["location"]
          raise "Redirect did not include a destination" if location.blank?

          return fetch(URI.join(uri, location), temporary_path, redirects + 1)
        end
        raise "Download failed with HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        bytes = 0
        File.open(temporary_path, "wb") do |file|
          response.read_body do |chunk|
            handle_control_request! if (bytes % 1.megabyte) < chunk.bytesize
            file.write(chunk)
            bytes += chunk.bytesize
            @download.update_columns(downloaded_bytes: bytes, updated_at: Time.current) if (bytes % 1.megabyte) < chunk.bytesize
          end
        end
        final_path = destination_path
        File.rename(temporary_path, final_path)
        @download.update!(downloaded_bytes: bytes)
      end
    end
  end

  def handle_control_request!
    @download.reload
    raise TransferCancelled, :stop if @download.status == "cancel_requested"
    raise TransferCancelled, :delete if @download.status == "delete_requested"
  end

  def handle_cancellation(action)
    File.delete(@temporary_path) if @temporary_path && File.file?(@temporary_path)
    if action == :delete
      @download.purge!
    else
      @download.update!(status: "cancelled", downloaded_bytes: 0, error_message: nil)
    end
  end

  def validate_uri!(uri, initial: false)
    raise "Downloads require HTTPS" unless uri.is_a?(URI::HTTPS) && uri.port == 443
    raise "Unapproved catalog host" if initial && !ALLOWED_HOSTS.include?(uri.host)
    raise "Unapproved redirect host" if uri.host.blank? || uri.host == "localhost" || uri.host.end_with?(".local")

    addresses = @resolver.call(uri.host)
    raise "Download host did not resolve" if addresses.empty?
    raise "Download host resolved to a private address" unless addresses.all? { |value| public_address?(IPAddr.new(value)) }
  end

  def public_address?(address)
    BLOCKED_NETWORKS.none? { |network| network.include?(address) }
  end

  def destination_path
    @download.inferred_destination_path
  end
end
