class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  before_action :set_interface_state

  private

  def set_interface_state
    @theme = cookies[:theme].presence || "dark"
    @theme = "dark" unless @theme.in?(%w[dark light])
  end
end
