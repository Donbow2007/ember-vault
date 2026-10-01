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

  def install_stream
    model = ModelCatalog.find(params[:id])
    return render json: { error: "Unknown model." }, status: :not_found unless model

    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"

    ModelInstaller.new(model, progress: ->(downloaded, total) {
      percent = total.positive? ? ((downloaded.to_f / total) * 100).round : nil
      response.stream.write("data: #{ { downloaded:, total:, percent: }.to_json }\\n\\n")
    }).install!
    response.stream.write("data: #{ { complete: true }.to_json }\\n\\n")
  rescue StandardError => error
    response.stream.write("data: #{ { error: error.message }.to_json }\\n\\n") rescue nil
  ensure
    response.stream.close
  end

  def destroy
    model = ModelCatalog.find(params[:id])
    return redirect_to(models_path, alert: "Unknown model.") unless model

    ModelInstaller.new(model).remove!
    redirect_to models_path, notice: "#{model.display_name} removed."
  end
end
