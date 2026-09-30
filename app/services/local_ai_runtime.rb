require "json"
require "net/http"

class LocalAiRuntime
  class Error < StandardError; end
  class TimeoutError < Error; end
  class CancelledError < Error; end

  SYSTEM_PROMPT = <<~PROMPT.squish
    You are Ember, a calm offline survival and field-guide companion. Answer directly and practically.
    Prefer concise, field-ready instructions. State uncertainty when missing details materially affect safety.
    You are offline; never claim to have searched the internet or external documents.
  PROMPT

  attr_reader :profile

  def initialize(profile: nil)
    @entry = ModelCatalog.find(profile.presence || ENV["EMBER_VAULT_AI_PROFILE"].presence) ||
      ModelCatalog.installed.first || ModelCatalog.entries.first
    @profile = @entry&.id
  end

  def available?
    @entry.present? && ModelCatalog.model_path(@entry).file?
  end

  def status
    return :model_unconfigured unless @entry
    return :model_missing unless available?

    :ready
  end

  def generate(prompt, cancelled: -> { false })
    raise Error, "No local model is installed or available." unless available?
    raise CancelledError, "Local model response was stopped" if cancelled.call

    server.ensure_running!
    request = Net::HTTP::Post.new(server.endpoint)
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(
      model: @entry.id,
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: prompt.question }
      ],
      max_tokens: ENV.fetch("EMBER_VAULT_AI_TOKENS", "256").to_i,
      temperature: @entry.runtime.fetch("temperature", 0.6),
      repeat_penalty: @entry.runtime.fetch("repeat_penalty", 1.1),
      stream: false
    )

    response = Net::HTTP.start(server.endpoint.host, server.endpoint.port, open_timeout: 3, read_timeout: request_timeout) do |http|
      http.request(request)
    end
    raise Error, "Local model server returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    raise CancelledError, "Local model response was stopped" if cancelled.call

    content = JSON.parse(response.body).dig("choices", 0, "message", "content").to_s.strip
    raise Error, "Local model returned an empty response" if content.blank?

    content.first(12_000)
  rescue Net::ReadTimeout
    raise TimeoutError, "Local model response timed out"
  rescue JSON::ParserError => error
    raise Error, "Local model returned invalid JSON: #{error.message}"
  end

  private

  def server
    @server ||= LocalAiServer.new(entry: @entry)
  end

  def request_timeout
    ENV.fetch("EMBER_VAULT_AI_TIMEOUT", "180").to_i.clamp(10, 600)
  end
end
