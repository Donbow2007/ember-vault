require "open3"

class SetupController < ApplicationController
  AI_PROFILES = {
    "disabled" => { name: "No generative AI", model: nil, size_mb: 0, ram: "< 1 GB", description: "Use fast full-text search and exact source passages only." },
    "llama3.2-1b" => { name: "Llama 3.2 1B", model: "llama3.2:1b-text-q2_K", size_mb: 581, ram: "3 GB", description: "Smallest recommended general assistant for low-power hardware." },
    "deepseek-r1-1.5b" => { name: "DeepSeek R1 1.5B", model: "deepseek-r1:1.5b", size_mb: 1_126, ram: "4 GB", description: "Compact reasoning model with moderately higher memory use." }
  }.freeze

  def show
    @catalog = ContentCatalog.new
    @disk_free_mb = disk_free_mb
    @ai_profiles = AI_PROFILES
  end

  def create
    catalog = ContentCatalog.new
    selected_keys = Array(params[:packages]).compact_blank + params.fetch(:tiers, {}).values.compact_blank + [ params[:wikipedia] ].compact_blank
    resources = catalog.resolve(selected_keys)
    ai_profile = AI_PROFILES.key?(params[:ai_profile]) ? params[:ai_profile] : "disabled"
    theme = SetupConfiguration::THEMES.include?(params[:theme]) ? params[:theme] : "dark"
    capabilities = Array(params[:capabilities]).compact_blank & %w[information education]
    capabilities << "ai" unless ai_profile == "disabled"
    projected_size_mb = resources.sum { |resource| resource.fetch("size_mb", 0).to_i } + AI_PROFILES.fetch(ai_profile).fetch(:size_mb)

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

  def disk_free_mb
    output, status = Open3.capture2("df", "-Pm", Rails.root.to_s)
    status.success? ? output.lines.last.split[3].to_i : 0
  end
end
