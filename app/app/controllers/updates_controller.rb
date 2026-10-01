class UpdatesController < ApplicationController
  before_action :require_local_update_access, only: :install

  def show
    @update = ApplicationUpdate.new
    @status = @update.status
    @installed_models = ModelCatalog.installed
    @active_model = ModelCatalog.active
    @ai_running = @active_model.present? && LocalAiServer.new(entry: @active_model).running?
    render :index
  end

  def check
    update = ApplicationUpdate.new
    latest = update.latest_revision
    available = update.update_available?(latest)
    message = available ? "Update available: #{latest.first(8)}" : "Ember Vault is up to date."
    update.write_status(state: available ? "available" : "current", message:)
    redirect_to updates_path, notice: message
  rescue StandardError => error
    redirect_to updates_path, alert: "Update check failed: #{error.message}"
  end

  def install
    ApplicationUpdate.new.write_status(state: "queued", message: "Update queued. Keep this device powered on.")
    ApplicationUpdateJob.perform_later
    redirect_to updates_path, notice: "Update queued. Refresh this page to see its status."
  end

  def select_model
    previous = ModelCatalog.active
    was_running = previous.present? && LocalAiServer.new(entry: previous).running?
    LocalAiServer.new(entry: previous).stop! if was_running
    model = ModelCatalog.select!(params[:model_id])
    LocalAiServer.new(entry: model).start! if was_running
    redirect_to updates_path, notice: "#{model.display_name} selected#{was_running ? " and AI server restarted." : "."}"
  rescue StandardError => error
    redirect_to updates_path, alert: "Could not select model: #{error.message}"
  end

  def restart_ai
    model = ModelCatalog.active
    return redirect_to(updates_path, alert: "Install a model first.") unless model

    LocalAiServer.new(entry: model).restart!
    redirect_to updates_path, notice: "AI server restarted with #{model.display_name}."
  rescue StandardError => error
    redirect_to updates_path, alert: "AI server failed to restart: #{error.message}"
  end

  private

  def require_local_update_access
    return if request.local? || ENV["ALLOW_REMOTE_UPDATES"] == "1"

    redirect_to updates_path, alert: "Updates may only be installed from this device."
  end
end
