class KnowledgePackQueue
  def initialize(result: RemoteKnowledgeCatalog.new.fetch) = @result = result

  def call(package_ids)
    raise "Knowledge catalog is offline" unless @result.online
    selected = Array(package_ids).compact_blank
    RemoteKnowledgeCatalog.new.packages(result: @result).select { |pack| selected.include?(pack["id"]) }.filter_map do |pack|
      download = ContentDownload.find_or_initialize_by(package_id: pack.fetch("id"))
      same_installed = download.installed_package_version == pack.fetch("version") && download.installed_content_hash == pack.fetch("content_hash")
      next if same_installed && download.status == "installed"
      next if download.persisted? && download.active?
      download.assign_attributes(resource_id: "knowledge-pack:#{pack.fetch('id')}", title: pack.fetch("name"),
        source_url: pack.fetch("download_url"), kind: "knowledge-pack", expected_bytes: pack.fetch("download_size", 0),
        package_version: pack.fetch("version"), content_hash: pack.fetch("content_hash"), status: "queued",
        downloaded_bytes: 0, error_message: nil)
      download.save!
      ContentDownloadJob.perform_later(download)
      download
    end
  end
end
