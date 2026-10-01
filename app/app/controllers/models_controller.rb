class ModelsController < ApplicationController
  skip_before_action :require_onboarding

  def index
    @models = ModelCatalog.entries
    @installed_ids = ModelCatalog.installed.map(&:id)
    @active_model = ModelCatalog.active
    @ai_running = @active_model.present? && LocalAiServer.new(entry: @active_model).running?
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
      response.stream.write("data: #{ { downloaded:, total:, percent: }.to_json }\n\n")
    }).install!
    response.stream.write("data: #{ { complete: true }.to_json }\n\n")
  rescue StandardError => error
    response.stream.write("data: #{ { error: error.message }.to_json }\n\n") rescue nil
  ensure
    response.stream.close
  end

  def select
    previous = ModelCatalog.active
    was_running = previous.present? && LocalAiServer.new(entry: previous).running?
    LocalAiServer.new(entry: previous).stop! if was_running

    model = ModelCatalog.select!(params[:id])
    LocalAiServer.new(entry: model).start! if was_running
    redirect_to models_path, notice: "#{model.display_name} selected#{was_running ? " and AI server restarted." : "."}"
  rescue StandardError => error
    redirect_to models_path, alert: "Could not select model: #{error.message}"
  end

  def start_server
    model = ModelCatalog.active
    return redirect_to(models_path, alert: "Install and select a model first.") unless model

    LocalAiServer.new(entry: model).start!
    redirect_to models_path, notice: "AI server started with #{model.display_name}."
  rescue StandardError => error
    redirect_to models_path, alert: "AI server failed to start: #{error.message}"
  end

  def stop_server
    model = ModelCatalog.active || ModelCatalog.installed.first
    LocalAiServer.new(entry: model).stop! if model
    redirect_to models_path, notice: "AI server stopped."
  rescue StandardError => error
    redirect_to models_path, alert: "AI server failed to stop: #{error.message}"
  end

  def shutdown
    model = ModelCatalog.active || ModelCatalog.installed.first
    LocalAiServer.new(entry: model).stop! if model
    Thread.new do
      sleep 0.5
      Process.kill(Gem.win_platform? ? "KILL" : "TERM", Process.pid)
    end
    render plain: "Ember Vault is shutting down. You can close this browser tab."
  end

  def destroy
    model = ModelCatalog.find(params[:id])
    return redirect_to(models_path, alert: "Unknown model.") unless model

    ModelInstaller.new(model).remove!
    redirect_to models_path, notice: "#{model.display_name} removed."
  end
end
