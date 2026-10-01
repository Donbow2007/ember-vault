class SettingsController < ApplicationController
  THEMES = %w[dark light].freeze

  def theme
    selected_theme = params[:theme].to_s
    unless selected_theme.in?(THEMES)
      redirect_back fallback_location: root_path(anchor: "system"), alert: "Unknown display theme."
      return
    end

    cookies.permanent[:theme] = { value: selected_theme, same_site: :lax }
    redirect_back fallback_location: root_path(anchor: "system"), notice: "Display changed to #{selected_theme} mode."
  end
end
