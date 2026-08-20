require "open3"
require "pathname"

class StorageMetrics
  EMPTY = { total: 0, used: 0, available: 0, percent: 0 }.freeze

  def initialize(path = EmberVault::Paths.data_root)
    @path = Pathname.new(path).expand_path
  end

  def call
    Gem.win_platform? ? windows_usage : unix_usage
  rescue Errno::ENOENT, RuntimeError
    EMPTY.dup
  end

  private

  def unix_usage
    output, status = Open3.capture2("df", "-Pk", @path.to_s)
    fields = output.lines.last.to_s.split
    return EMPTY.dup unless status.success? && fields.length >= 6

    total = fields[-5].to_i.kilobytes
    used = fields[-4].to_i.kilobytes
    available = fields[-3].to_i.kilobytes
    percent = total.positive? ? (used.to_f / total * 100).round : 0
    { total:, used:, available:, percent: }
  end

  def windows_usage
    drive = @path.to_s[/\A[A-Za-z]:/]
    return EMPTY.dup unless drive

    name = drive.delete_suffix(":")
    command = "$d=Get-PSDrive -Name '#{name}'; Write-Output \"$($d.Used),$($d.Free)\""
    output, status = Open3.capture2("powershell.exe", "-NoProfile", "-NonInteractive", "-Command", command)
    return EMPTY.dup unless status.success?

    used, available = output.strip.split(",", 2).map(&:to_i)
    total = used + available
    percent = total.positive? ? (used.to_f / total * 100).round : 0
    { total:, used:, available:, percent: }
  end
end
