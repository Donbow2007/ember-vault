require "digest"
require "fileutils"
require "net/http"

class ModelInstaller
  class Error < StandardError; end

  def initialize(entry)
    @entry = entry
  end

  def install!
    raise Error, "Model has no download URL" if @entry.download_url.blank?

    EmberVault::PortableStorage.prepare!
    destination = ModelCatalog.model_path(@entry)
    temporary = Pathname.new("#{destination}.part")
    download(URI(@entry.download_url), temporary)
    verify!(temporary)
    FileUtils.mv(temporary, destination)
    destination
  rescue StandardError
    FileUtils.rm_f(temporary) if defined?(temporary)
    raise
  end

  def remove!
    FileUtils.rm_f(ModelCatalog.model_path(@entry))
  end

  private

  def download(uri, destination, redirects = 0)
    raise Error, "Too many model download redirects" if redirects > 5

    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 120) do |http|
      response = http.get(uri.request_uri)
      if response.is_a?(Net::HTTPRedirection)
        return download(URI.join(uri, response["location"]), destination, redirects + 1)
      end
      raise Error, "Model download failed with HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      File.open(destination, "wb") { |file| response.read_body { |chunk| file.write(chunk) } }
    end
  end

  def verify!(path)
    expected = @entry.sha256
    return if expected.blank?
    actual = Digest::SHA256.file(path).hexdigest
    raise Error, "Model checksum mismatch" unless ActiveSupport::SecurityUtils.secure_compare(actual, expected)
  end
end
