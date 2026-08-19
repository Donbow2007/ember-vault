require "open3"

class SetupController < ApplicationController
  AI_MODEL_RESOURCES = {
    "smollm2-135m" => {
      "id" => "smollm2-135m",
      "title" => "SmolLM2 135M Instruct (Q4_K_M)",
      "url" => "https://huggingface.co/bartowski/SmolLM2-135M-Instruct-GGUF/resolve/main/SmolLM2-135M-Instruct-Q4_K_M.gguf",
      "kind" => "model",
      "size_mb" => 105
    },
    "smollm2-360m" => {
      "id" => "smollm2-360m",
      "title" => "SmolLM2 360M Instruct (Q4_K_M)",
      "url" => "https://huggingface.co/bartowski/SmolLM2-360M-Instruct-GGUF/resolve/main/SmolLM2-360M-Instruct-Q4_K_M.gguf",
      "kind" => "model",
      "size_mb" => 271
    }
  }.freeze

  AI_PROFILES = {
    "disabled" => { name: "Search only", model: nil, size_mb: 0, ram: "< 512 MB", description: "Use full-text search and open exact source passages without an answer assistant." },
    "source-assistant" => { name: "Cited source assistant", model: nil, size_mb: 0, ram: "512 MB", description: "Recommended for Raspberry Pi 3 B. Displays fast answers from retrieved passages and always links the original sources." },
    "smollm2-135m" => { name: "SmolLM2 135M", model: "SmolLM2-135M-Instruct-Q4_K_M.gguf", size_mb: 105, ram: "768 MB + swap", description: "Shows the cited answer immediately, then attempts an optional four-second local refinement." },
    "smollm2-360m" => { name: "SmolLM2 360M", model: "SmolLM2-360M-Instruct-Q4_K_M.gguf", size_mb: 271, ram: "1 GB + swap", description: "Experimental refinement tier for faster hardware. The immediate cited answer never waits for it." }
  }.freeze

  def show
    @catalog = ContentCatalog.new
    @disk_usage = disk_usage
    @disk_free_mb = @disk_usage.fetch(:available).to_f / 1.megabyte
    @ai_profiles = AI_PROFILES
  end

  def create
    catalog = ContentCatalog.new
    selected_keys = Array(params[:packages]).compact_blank + params.fetch(:tiers, {}).values.compact_blank + [ params[:wikipedia] ].compact_blank
    resources = catalog.resolve(selected_keys)
    ai_profile = AI_PROFILES.key?(params[:ai_profile]) ? params[:ai_profile] : "disabled"
    resources << AI_MODEL_RESOURCES.fetch(ai_profile) if AI_MODEL_RESOURCES.key?(ai_profile)
    theme = SetupConfiguration::THEMES.include?(params[:theme]) ? params[:theme] : "dark"
    capabilities = Array(params[:capabilities]).compact_blank & %w[information education]
    capabilities << "ai" unless ai_profile == "disabled"
    projected_size_mb = resources.sum { |resource| resource.fetch("size_mb", 0).to_i }

    configuration = SetupConfiguration.create!(capabilities:, selected_resources: selected_keys,
      ai_profile:, theme:, projected_size_mb:, completed_at: Time.current)
    cookies.permanent[:theme] = { value: theme, same_site: :lax }
    resources.each do |resource|
      download = ContentDownload.find_or_initialize_by(resource_id: resource.fetch("id"))
      download.assign_attributes(title: resource.fetch("title"), source_url: resource.fetch("url"),
        kind: resource.fetch("kind"), expected_bytes: resource.fetch("size_mb", 0).to_i.megabytes,
        status: download.status == "complete" ? "complete" : "queued")
      download.save!
      ContentDownloadJob.perform_later(download) unless download.status == "complete"
    end
    redirect_to setup_complete_path(configuration_id: configuration.id)
  end

  def complete
    @configuration = SetupConfiguration.find(params[:configuration_id])
    @downloads = ContentDownload.order(:created_at)
  end

  private

  def disk_usage
    output, status = Open3.capture2("df", "-Pk", Rails.root.to_s)
    fields = output.lines.last.to_s.split
    return { used: 0, available: 0, total: 0, percent: 0 } unless status.success? && fields.length >= 6

    used = fields[2].to_i.kilobytes
    available = fields[3].to_i.kilobytes
    total = used + available
    percent = total.positive? ? (used.to_f / total * 100).round(2) : 0
    { used:, available:, total:, percent: }
  end
end
