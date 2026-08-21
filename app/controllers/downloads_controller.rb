class DownloadsController < ApplicationController
  before_action :disable_browser_cache

  def index
    @downloads = ContentDownload.order(created_at: :desc)
    catalog = ContentCatalog.new
    @map_jurisdictions = catalog.map_jurisdictions
    @map_state = params[:map_state].to_s.strip
    @map_query = params[:map_q].to_s.strip
    @catalog_query = params[:catalog_q].to_s.strip
    @remote_query = params[:remote_q].to_s.strip
    @catalog_results = ContentDiscovery.new.local(@catalog_query) if @catalog_query.present?
    @remote_results = ContentDiscovery.new.remote(@remote_query) if @remote_query.present?
    @map_results = ContentDiscovery.new.maps(query: @map_query, jurisdiction: @map_state) if @map_query.present? || @map_state.present?
    installed_ids = @downloads.pluck(:resource_id).to_set
    @catalog_results&.reject! { |result| installed_ids.include?(result.resource_id) }
    @remote_results&.reject! { |result| installed_ids.include?(result.resource_id) }
    @installed_resource_ids = installed_ids
  end

  def status
    @downloads = ContentDownload.order(created_at: :desc)
    render partial: "queue_contents", locals: { downloads: @downloads }
  end

  def retry_failed
    downloads = ContentDownload.where(status: "failed")
    count = downloads.count
    downloads.find_each do |download|
      download.update!(status: "queued", error_message: nil, downloaded_bytes: 0)
      ContentDownloadJob.perform_later(download)
    end
    redirect_to downloads_path, notice: "#{count} failed downloads returned to the queue."
  end

  def destroy_all
    count = ContentDownload.count
    ContentDownload.find_each do |download|
      if download.status.in?(%w[queued downloading cancel_requested])
        download.update!(status: "delete_requested")
      elsif download.status != "deleting"
        download.enqueue_deletion!
      end
    end
    redirect_to downloads_path, notice: "Deletion queued for #{count} #{'download'.pluralize(count)}."
  end

  def install
    result = ContentDiscovery.verify(params.require(:token))
    download = ContentDownload.find_or_initialize_by(resource_id: result.resource_id)
    if download.persisted?
      notice = "#{download.title} is already in the transfer library."
    else
      download.update!(title: result.title, source_url: result.source_url, kind: result.kind,
        expected_bytes: result.size_bytes.to_i, status: "queued")
      ContentDownloadJob.perform_later(download)
      notice = "#{download.title} added to the transfer queue."
    end
    redirect_to downloads_path, notice:
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActionController::ParameterMissing
    redirect_to downloads_path, alert: "That discovery result expired. Search again before installing."
  end

  def reindex_all
    downloads = ContentDownload.where(kind: %w[zim document], status: "complete").where.not(destination_path: nil)
    downloads.find_each(&:enqueue_indexing!)
    redirect_to documents_path, notice: "#{downloads.count} downloaded archives queued for reindexing."
  end

  def stop
    download = ContentDownload.find(params[:id])
    download.update!(status: "cancel_requested") if download.status.in?(%w[queued downloading])
    redirect_to downloads_path, notice: "Stop requested for #{download.title}."
  end

  def retry_download
    download = ContentDownload.find(params[:id])
    if download.status.in?(%w[cancelled failed])
      download.remove_content_files
      download.update!(status: "queued", downloaded_bytes: 0, error_message: nil, destination_path: nil)
      ContentDownloadJob.perform_later(download)
    end
    redirect_to downloads_path, notice: "#{download.title} returned to the queue."
  end

  def retry_deletion
    download = ContentDownload.find(params[:id])
    download.enqueue_deletion! if download.status == "deletion_failed"
    redirect_to downloads_path, notice: "Deletion returned to the queue for #{download.title}."
  end

  def index_content
    download = ContentDownload.find(params[:id])
    if download.kind.in?(%w[zim document]) && download.status == "complete"
      download.enqueue_indexing!
      notice = "#{download.title} queued for indexing."
    else
      notice = "Only completed document downloads can be indexed."
    end
    redirect_to documents_path, notice:
  end

  def search_index
    download = ContentDownload.find(params[:id])
    download.documents.find_each do |document|
      total = document.passages.count
      document.update!(status: "deleting", deletion_total: total, deletion_remaining: total, error_message: nil)
      DeleteDocumentJob.perform_later(document)
    end
    redirect_to documents_path, notice: "Search index deletion queued for #{download.title}."
  end

  def destroy
    download = ContentDownload.find(params[:id])
    if download.status.in?(%w[queued downloading cancel_requested])
      download.update!(status: "delete_requested")
      notice = "Deletion requested for #{download.title}; its worker is shutting down."
    else
      download.enqueue_deletion! unless download.status == "deleting"
      notice = "#{download.title} was queued for deletion."
    end
    redirect_to downloads_path, notice:
  end

  private

  def disable_browser_cache
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"
  end
end
