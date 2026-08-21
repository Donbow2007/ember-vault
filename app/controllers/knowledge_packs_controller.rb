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
    KnowledgePackQueue.new(result:).call(params[:packages])
    redirect_to knowledge_packs_path, notice: "Selected knowledge packs are queued."
  end
  private
  def load_catalog
    @catalog_result = RemoteKnowledgeCatalog.new.fetch
    @categories = @catalog_result.manifest.fetch("categories", [])
    @installed = ContentDownload.where.not(package_id: nil).index_by(&:package_id)
  end
end
