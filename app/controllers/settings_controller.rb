class SettingsController < ApplicationController
  def theme
    selected_theme = params[:theme].to_s
    return redirect_back fallback_location: root_path(anchor: "system"), alert: "Unknown display theme." unless selected_theme.in?(SetupConfiguration::THEMES)

    cookies.permanent[:theme] = { value: selected_theme, same_site: :lax }
    SetupConfiguration.order(created_at: :desc).first&.update!(theme: selected_theme)
    redirect_back fallback_location: root_path(anchor: "system"), notice: "Display changed to #{selected_theme} mode."
  end

  def ai_profile
    selected_profile = params[:ai_profile].to_s
    unless LocalAiRuntime.selectable_profiles.key?(selected_profile)
      return redirect_back fallback_location: root_path(anchor: "system"), alert: "That AI model is not downloaded and ready."
    end

    configuration = SetupConfiguration.order(created_at: :desc).first
    if configuration
      configuration.update!(ai_profile: selected_profile)
    else
      SetupConfiguration.create!(capabilities: [ "ai" ], selected_resources: [ selected_profile ],
        ai_profile: selected_profile, theme: @theme, projected_size_mb: 0, completed_at: Time.current)
    end
    redirect_back fallback_location: root_path(anchor: "system"), notice: "Active AI changed to #{LocalAiRuntime::PROFILE_NAMES.fetch(selected_profile)}."
  end
end
