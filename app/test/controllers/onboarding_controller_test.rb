require "test_helper"
require "fileutils"

class OnboardingControllerTest < ActionDispatch::IntegrationTest
  setup do
    @marker = EmberVault::PortableStorage.path("settings", "onboarding.complete")
    FileUtils.rm_f(@marker)
  end

  teardown { FileUtils.rm_f(@marker) }

  test "first launch shows onboarding" do
    get onboarding_path
    assert_response :success
    assert_select "h1", /Get ready/
  end

  test "completing setup writes portable marker" do
    post complete_onboarding_path
    assert_redirected_to root_path
    assert @marker.file?
  end
end
