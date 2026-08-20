require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  test "changes and persists the display theme from system settings" do
    patch theme_setting_url, params: { theme: "light" }, headers: { "HTTP_REFERER" => root_url(anchor: "system") }

    assert_redirected_to root_url(anchor: "system")
    follow_redirect!
    assert_select "body[data-theme='light']"
    assert_select ".system-theme strong", text: "LIGHT"
  end

  test "rejects an unknown display theme" do
    patch theme_setting_url, params: { theme: "unknown" }

    assert_redirected_to root_url(anchor: "system")
  end

  test "changes the active AI to a downloaded model" do
    configuration = SetupConfiguration.create!(capabilities: [ "ai" ], selected_resources: [ "source-assistant" ],
      ai_profile: "source-assistant", theme: "dark", projected_size_mb: 0, completed_at: Time.current)
    model_path = EmberVault::Paths.models.join("smollm2-135m.gguf")
    model_was_present = model_path.file?
    FileUtils.mkdir_p(model_path.dirname)
    File.binwrite(model_path, "test model") unless model_was_present
    ContentDownload.create!(resource_id: "smollm2-135m", title: "SmolLM2 135M",
      source_url: "https://huggingface.co/model.gguf", kind: "model", status: "complete",
      destination_path: "models/smollm2-135m.gguf", downloaded_bytes: model_path.size)

    patch ai_profile_setting_url, params: { ai_profile: "smollm2-135m" },
      headers: { "HTTP_REFERER" => root_url(anchor: "system") }

    assert_redirected_to root_url(anchor: "system")
    assert_equal "smollm2-135m", configuration.reload.ai_profile
  ensure
    File.delete(model_path) if model_path && !model_was_present && model_path.file?
  end

  test "rejects an AI model that is not downloaded" do
    patch ai_profile_setting_url, params: { ai_profile: "smollm2-135m" }

    assert_redirected_to root_url(anchor: "system")
    assert_nil SetupConfiguration.order(created_at: :desc).first
  end
end
