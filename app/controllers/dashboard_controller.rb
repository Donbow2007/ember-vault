class DashboardController < ApplicationController
  def index
    @query = params[:q].to_s.strip
    if @query.present?
      @results = Passage.search(@query)
      map_scope = MapFeature.joins(:content_download)
        .where(content_downloads: { kind: "map", status: "complete" }).includes(:content_download)
      @map_results = MapSearch.new(map_scope).call(@query, limit: 10)
    end
    @document_count = Document.where(status: "ready").count
    @passage_count = Passage.count
    @map_count = ContentDownload.where(kind: "map", status: "complete").count
    @ai_runtime = LocalAiRuntime.new
    disk = disk_usage
    @modules = @navigation_modules
    @metrics = [
      { label: "DEVICE STORAGE", value: "#{human_size(disk[:used])} USED / #{human_size(disk[:available])} FREE", percent: disk[:percent] },
      { label: "ARCHIVE HEALTH", value: "NOMINAL", percent: 100 },
      { label: "INDEX STATUS", value: "#{@passage_count} PASSAGES", percent: @passage_count.positive? ? 100 : 5 },
      { label: "UPTIME", value: "JUST STARTED", percent: 2 }
    ]
  end

  private

  def disk_usage
    StorageMetrics.new.call
  end

  def human_size(bytes)
    ActiveSupport::NumberHelper.number_to_human_size(bytes, precision: 3)
  end
end
