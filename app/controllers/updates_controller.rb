class UpdatesController < ApplicationController
  before_action :require_local_update_access, only: :install

  def show
    @update = ApplicationUpdate.new
    @status = @update.status
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

  private

  def require_local_update_access
    return if request.local? || ENV["ALLOW_REMOTE_UPDATES"] == "1"

    redirect_to updates_path, alert: "Updates may only be installed from this device."
  end
end
