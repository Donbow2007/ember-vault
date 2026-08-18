class SettingsController < ApplicationController
  def theme
    selected_theme = params[:theme].to_s
    return redirect_back fallback_location: root_path(anchor: "system"), alert: "Unknown display theme." unless selected_theme.in?(SetupConfiguration::THEMES)

    cookies.permanent[:theme] = { value: selected_theme, same_site: :lax }
    SetupConfiguration.order(created_at: :desc).first&.update!(theme: selected_theme)
    redirect_back fallback_location: root_path(anchor: "system"), notice: "Display changed to #{selected_theme} mode."
  end
end
