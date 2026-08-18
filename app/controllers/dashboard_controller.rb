require "open3"

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
    output, status = Open3.capture2("df", "-Pk", Rails.root.to_s)
    fields = output.lines.last.to_s.split
    return { used: 0, available: 0, percent: 0 } unless status.success? && fields.length >= 6

    used = fields[2].to_i.kilobytes
    available = fields[3].to_i.kilobytes
    total_available = used + available
    percent = total_available.positive? ? (used.to_f / total_available * 100).round : 0
    { used:, available:, percent: }
  end

  def human_size(bytes)
    ActiveSupport::NumberHelper.number_to_human_size(bytes, precision: 3)
  end
end
