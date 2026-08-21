class KnowledgePacksController < ApplicationController
  def show
    load_catalog
  end
  def refresh
    redirect_to knowledge_packs_path, notice: "Knowledge catalog refreshed."
  end
  def install
    result = RemoteKnowledgeCatalog.new.fetch
    return redirect_to(knowledge_packs_path, alert: "Offline — downloads are unavailable.") unless result.online
    selected = Array(params[:packages]); catalog = RemoteKnowledgeCatalog.new
    catalog.packages(result:).select { |pack| selected.include?(pack["id"]) }.each do |pack|
      download = ContentDownload.find_or_initialize_by(package_id: pack.fetch("id"))
      download.assign_attributes(resource_id: "knowledge-pack:#{pack.fetch('id')}", title: pack.fetch("name"), source_url: pack.fetch("download_url"), kind: "knowledge-pack", expected_bytes: pack.fetch("download_size", 0), package_version: pack.fetch("version"), content_hash: pack.fetch("content_hash"), status: "queued", downloaded_bytes: 0)
      download.save!; ContentDownloadJob.perform_later(download)
    end
    redirect_to knowledge_packs_path, notice: "Selected knowledge packs are queued."
  end
  private
  def load_catalog
    @catalog_result = RemoteKnowledgeCatalog.new.fetch
    @categories = @catalog_result.manifest.fetch("categories", [])
    @installed = ContentDownload.where.not(package_id: nil).index_by(&:package_id)
  end
end
