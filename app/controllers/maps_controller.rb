class MapsController < ApplicationController
  def index
    MapPackDiscovery.new.call
    @maps = MapPack.includes(:map_features).order(:title)
  end

  def show
    @map_pack = map_pack
    @selected_feature = @map_pack.map_features.find_by(id: params[:feature_id])
  end

  def archive
    pack = map_pack
    path = pack.archive_path
    if File.file?(path)
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
