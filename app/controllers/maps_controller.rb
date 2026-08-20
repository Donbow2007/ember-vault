class MapsController < ApplicationController
  def index
    @maps = ContentDownload.where(kind: "map", status: "complete").includes(:map_features).order(:title)
  end

  def show
    @map_download = completed_map
    @selected_feature = @map_download.map_features.find_by(id: params[:feature_id])
  end

  def archive
    download = completed_map
    path = EmberVault::Paths.resolve(download.destination_path)
    content_root = EmberVault::Paths.content_for("map")
    return head :not_found unless EmberVault::Paths.within?(path, content_root) && File.file?(path)

    response.headers["Accept-Ranges"] = "bytes"
    response.headers["Cache-Control"] = "private, max-age=3600"
    return serve_range(path, request.headers["Range"]) if request.headers["Range"].present?

    send_file path, type: "application/octet-stream", disposition: "inline"
  rescue ArgumentError
    head :not_found
  end

  def search
    download = completed_map
    ranked = MapSearch.new(download.map_features).call(params[:q])
    render json: ranked.as_json(only: %i[id name category kind latitude longitude])
  end

  def reindex
    download = completed_map
    download.enqueue_map_indexing!
    redirect_to documents_path, notice: "#{download.title} queued for geographic reindexing."
  end

  private

  def completed_map
    ContentDownload.where(kind: "map", status: "complete").find(params[:id])
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
