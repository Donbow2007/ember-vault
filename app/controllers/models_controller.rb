class ModelsController < ApplicationController
  skip_before_action :require_onboarding

  def index
    @models = ModelCatalog.entries
    @installed_ids = ModelCatalog.installed.map(&:id)
  end

  def install
    model = ModelCatalog.find(params[:id])
    return redirect_to(models_path, alert: "Unknown model.") unless model

    ModelInstaller.new(model).install!
    redirect_to models_path, notice: "#{model.display_name} installed."
  rescue ModelInstaller::Error, StandardError => error
    redirect_to models_path, alert: "Model install failed: #{error.message}"
  end

  def destroy
    model = ModelCatalog.find(params[:id])
    return redirect_to(models_path, alert: "Unknown model.") unless model

    ModelInstaller.new(model).remove!
    redirect_to models_path, notice: "#{model.display_name} removed."
  end
end
