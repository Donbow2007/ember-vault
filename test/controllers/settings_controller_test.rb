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
end
