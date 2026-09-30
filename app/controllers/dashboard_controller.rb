require "open3"

class DashboardController < ApplicationController
  def index
    @ai_runtime = LocalAiRuntime.new
    @map_count = MapPack.count
    @disk = disk_usage
  end

  private

  def disk_usage
    root = ENV.fetch("EMBER_VAULT_DATA_DIR", Rails.root.join("storage").to_s)
    output, status = Open3.capture2("df", "-Pk", root)
    fields = output.lines.last.to_s.split
    unless status.success? && fields.length >= 6
      return { used: 0, available: 0, percent: 0 }
    end

    used = fields[2].to_i.kilobytes
    available = fields[3].to_i.kilobytes
    total = used + available
    { used:, available:, percent: total.positive? ? (used.to_f / total * 100).round : 0 }
  end
end
