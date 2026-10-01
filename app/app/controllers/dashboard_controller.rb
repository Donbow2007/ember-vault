class DashboardController < ApplicationController
  def index
    @ai_runtime = LocalAiRuntime.new
    @map_count = MapPack.count
    @disk = disk_usage
  end

  private

  def disk_usage
    root = EmberVault::PortableStorage.root
    available = if Gem.win_platform?
      windows_available_bytes(root)
    else
      unix_available_bytes(root)
    end
    { available:, percent: 0 }
  rescue StandardError
    { available: 0, percent: 0 }
  end

  def unix_available_bytes(root)
    output = IO.popen([ "df", "-Pk", root.to_s ], &:read)
    output.lines.last.to_s.split[3].to_i.kilobytes
  end

  def windows_available_bytes(root)
    drive = root.to_s[0, 2]
    output = IO.popen([ "powershell", "-NoProfile", "-Command", "(Get-PSDrive '#{drive[0]}').Free" ], &:read)
    output.to_i
  end
end
