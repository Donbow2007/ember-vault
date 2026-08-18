require "test_helper"

class SetupControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "renders the complete upstream content catalog" do
    get setup_url
    assert_response :success
    assert_select "h1", text: "Choose your systems."
    assert_select "input[value='wikipedia:top-mini']"
    assert_select "input[value^='tier:']", minimum: 1
    assert_select "input[value^='map:']", minimum: 1
    assert_select "input[name='ai_profile'][value='source-assistant'][checked]"
    assert_select "input[name='ai_profile'][value='smollm2-135m']"
    assert_select "input[name='ai_profile'][value='llama3.2-1b']", count: 0
    assert_select "input[name='theme'][value='dark'][checked]"
    assert_select "input[name='theme'][value='light']"
    assert_select "input[type='radio'][data-action*='wizard#toggleRadio']", minimum: 1
    assert_select "label[data-action='pointerdown->wizard#rememberRadio']", minimum: 1
  end

  test "saves setup and queues selected public resource" do
    assert_enqueued_with(job: ContentDownloadJob) do
      post setup_url, params: {
        capabilities: [ "information" ],
        wikipedia: "wikipedia:top-mini",
        packages: [],
        tiers: {},
        ai_profile: "source-assistant",
        theme: "light"
      }
    end

    assert_redirected_to setup_complete_url(configuration_id: SetupConfiguration.last.id)
    assert_equal "source-assistant", SetupConfiguration.last.ai_profile
    assert_equal "light", SetupConfiguration.last.theme
    assert_includes SetupConfiguration.last.capabilities, "ai"
    assert_equal "https://download.kiwix.org", URI(ContentDownload.last.source_url).then { |uri| "#{uri.scheme}://#{uri.host}" }

    follow_redirect!
    assert_select "body[data-theme='light']"
    assert_select ".completion-page", text: /Theme: Light/
  end
end
