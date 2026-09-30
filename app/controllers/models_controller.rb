class ModelsController < ApplicationController
  def index
    @models = ModelCatalog.entries
    @installed_ids = ModelCatalog.installed.map(&:id)
  end
end
