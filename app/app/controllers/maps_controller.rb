class MapsController < ApplicationController
  skip_before_action :require_onboarding, only: [ :index, :install, :status ]

  def index
    MapPackDiscovery.new.call
    @catalog = MapCatalog.entries
    @maps = MapPack.order(:title)
    @packs_by_catalog_id = @maps.index_by(&:catalog_id)
  end

  def status
    @maps = MapPack.order(:title)
    render json: @maps.map { |map| {
      id: map.id, catalog_id: map.catalog_id, status: map.status, progress: map.progress,
      downloaded_bytes: map.downloaded_bytes, expected_bytes: map.expected_bytes,
      error_message: map.error_message, url: (map.installed? ? map_path(map) : nil)
    } }
  end

  def install
    entry = MapCatalog.find(params[:catalog_id])
    pack = MapPack.find_or_initialize_by(catalog_id: entry.id)
    if pack.persisted? && pack.status.in?(%w[queued downloading complete])
      return redirect_to maps_path, notice: "#{entry.title} is already installed or downloading."
    end

    pack.assign_attributes(
      title: entry.title,
      stored_path: File.join("maps", entry.id, "#{entry.id}.pmtiles"),
      format: "pmtiles", region: entry.region, catalog_version: entry.version,
      source_url: entry.url, expected_bytes: entry.size_mb.megabytes,
      downloaded_bytes: 0, status: "queued", error_message: nil
    )
    pack.save!
    MapDownloadJob.perform_later(pack)
    redirect_to maps_path, notice: "#{entry.title} added to the map download queue."
  end

  def destroy
    pack = map_pack
    title = pack.title
    directory = pack.pack_path.dirname
    pack.destroy!
    FileUtils.rm_rf(directory) if directory.to_s.start_with?("#{EmberVault::PortableStorage.path("maps").expand_path}#{File::SEPARATOR}")
    redirect_to maps_path, notice: "#{title} removed."
  end

  def show
    @map_pack = map_pack
    return redirect_to(maps_path, alert: "That map is not installed.") unless @map_pack.installed?

    @selected_feature = @map_pack.map_features.find_by(id: params[:feature_id])
  end

  def archive
    pack = map_pack
    path = pack.archive_path
    if pack.installed?
      response.headers["Accept-Ranges"] = "bytes"
      response.headers["Cache-Control"] = "private, max-age=3600"
      if request.headers["Range"].present?
        serve_range(path, request.headers["Range"])
      else
        send_file path, type: "application/octet-stream", disposition: "inline"
      end
    else
      head :not_found
    end
  end

  def search
    ranked = MapSearch.new(map_pack.map_features).call(params[:q])
    render json: ranked.as_json(only: %i[id name category kind latitude longitude])
  end

  def reindex
    MapIndexJob.perform_later(map_pack)
    redirect_to maps_path, notice: "#{map_pack.title} queued for geographic reindexing."
  end

  private

  def map_pack
    MapPack.find(params[:id])
  end

  def serve_range(path, header)
    match = header.match(/\Abytes=(\d+)-(\d*)\z/)
    return head :range_not_satisfiable unless match

    file_size = File.size(path)
    first = match[1].to_i
    last = match[2].present? ? [ match[2].to_i, file_size - 1 ].min : file_size - 1
    return head :range_not_satisfiable if first >= file_size || last < first

    length = last - first + 1
    content = File.open(path, "rb") { |file| file.seek(first); file.read(length) }
    response.headers["Content-Range"] = "bytes #{first}-#{last}/#{file_size}"
    response.headers["Content-Length"] = length.to_s
    send_data content, status: :partial_content, type: "application/octet-stream", disposition: "inline"
  end
end
