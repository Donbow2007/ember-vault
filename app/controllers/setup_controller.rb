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
    "smollm2-135m" => { name: "SmolLM2 135M", model: "SmolLM2-135M-Instruct-Q4_K_M.gguf", size_mb: 105, ram: "768 MB + swap", description: "A legacy micro-model for minimum hardware. Ember keeps the conversational cited answer when this model copies text or cannot improve it." },
    "smollm2-360m" => { name: "SmolLM2 360M", model: "SmolLM2-360M-Instruct-Q4_K_M.gguf", size_mb: 271, ram: "1 GB + swap", description: "The strongest Pi-oriented option. It receives compact evidence and gets up to five seconds to make safe questions more conversational." }
  }.freeze

  def show
    @catalog = ContentCatalog.new
    @disk_usage = disk_usage
    @disk_free_mb = @disk_usage.fetch(:available).to_f / 1.megabyte
    @ai_profiles = AI_PROFILES
    @installed_ai_profiles = LocalAiRuntime.downloaded_profiles.to_set
    @selected_ai_profile = SetupConfiguration.order(created_at: :desc).pick(:ai_profile)
    @selected_ai_profile = "source-assistant" unless @selected_ai_profile.in?(AI_PROFILES.keys)
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
      new_download = download.new_record?
      file_available = download.file_available?
      needs_enqueue = new_download || (!file_available && !download.active?)
      download.assign_attributes(title: resource.fetch("title"), source_url: resource.fetch("url"),
        kind: resource.fetch("kind"), expected_bytes: resource.fetch("size_mb", 0).to_i.megabytes,
        status: file_available ? "complete" : (download.active? ? download.status : "queued"))
      download.assign_attributes(downloaded_bytes: 0, destination_path: nil, error_message: nil) if needs_enqueue && !new_download
      download.save!
      ContentDownloadJob.perform_later(download) if needs_enqueue
    end
    redirect_to setup_complete_path(configuration_id: configuration.id)
  end

  def complete
    @configuration = SetupConfiguration.find(params[:configuration_id])
    @downloads = ContentDownload.order(:created_at)
  end

  private

  def disk_usage
    StorageMetrics.new.call
  end
end
