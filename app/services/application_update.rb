require "net/http"
require "open3"

class ApplicationUpdate
  REPOSITORY = "Donbow2007/ember-vault"
  API_URI = URI("https://api.github.com/repos/#{REPOSITORY}/commits/main")

  def current_revision
    output, status = Open3.capture2e("git", "-C", Rails.root.to_s, "rev-parse", "HEAD")
    status.success? ? output.strip : "unknown"
  end

  def latest_revision
    request = Net::HTTP::Get.new(API_URI)
    request["Accept"] = "application/vnd.github+json"
    request["User-Agent"] = "Ember-Vault-Updater/#{current_version}"
    response = Net::HTTP.start(API_URI.host, API_URI.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
      http.request(request)
    end
    raise "GitHub returned #{response.code}." unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body).fetch("sha")
  rescue JSON::ParserError, KeyError
    raise "GitHub returned an invalid update response."
  end

  def current_version
    Rails.root.join("VERSION").read.strip
  rescue Errno::ENOENT
    "development"
  end

  def update_available?(latest)
    current_revision != latest
  end

  def status
    return {} unless status_path.file?

    JSON.parse(status_path.read).with_indifferent_access
  rescue JSON::ParserError
    {}
  end

  def write_status(state:, message:)
    status_path.dirname.mkpath
    status_path.write(JSON.pretty_generate(state:, message:, updated_at: Time.current.iso8601))
  end

  private

  def status_path
    EmberVault::Paths.data_root.join("update-status.json")
  end
end
