class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :set_navigation_modules

  private

  def set_navigation_modules
    @theme = cookies[:theme].presence || SetupConfiguration.order(created_at: :desc).pick(:theme)
    @theme = "dark" unless @theme.in?(SetupConfiguration::THEMES)
    document_count = Document.where(status: "ready").count
    map_count = ContentDownload.where(kind: "map", status: "complete").count
    @navigation_modules = []
    if document_count.positive?
      @navigation_modules << { name: "The Archive", status: "READY", icon: "archive-icon", size: "#{document_count} ITEMS",
        description: "Books, manuals, articles, and documents—indexed to the paragraph.", path: documents_path, controller: "documents" }
    end
    if map_count.positive?
      @navigation_modules << { name: "World Atlas", status: "READY", icon: "map-icon", size: "#{map_count} REGIONS",
        description: "Detailed offline maps and geographic intelligence for any terrain.", path: maps_path, controller: "maps" }
    end
  end
end
