class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  before_action :set_interface_state
  before_action :require_onboarding

  private

  def set_interface_state
    @theme = cookies[:theme].presence || "dark"
    @theme = "dark" unless @theme.in?(%w[dark light])
  end

  def require_onboarding
    return if controller_name == "onboarding"
    return if EmberVault::PortableStorage.path("settings", "onboarding.complete").file?

    redirect_to onboarding_path
  end
end
