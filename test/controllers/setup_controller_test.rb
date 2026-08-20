require "test_helper"

class SetupControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "renders the complete upstream content catalog" do
    get setup_url
    assert_response :success
    assert_select "title", text: "Setup — Ember Vault"
    assert_no_match(/Initial Setup/i, response.body)
    assert_select "h1", text: "Choose your systems."
    assert_select "input[value='wikipedia:top-mini']"
    assert_select "input[value^='tier:']", minimum: 1
    assert_select "input[value^='map:']", minimum: 1
    assert_select "input[name='ai_profile'][value='source-assistant'][checked]"
    assert_select "input[name='ai_profile'][value='smollm2-135m']"
    assert_select "input[name='ai_profile'][value='smollm2-360m']"
    assert_select "input[name='ai_profile'][value='llama3.2-1b']", count: 0
    assert_select "input[name='theme'][value='dark'][checked]"
    assert_select "input[name='theme'][value='light']"
    assert_select "input[type='radio'][data-action*='wizard#toggleRadio']", minimum: 1
    assert_select "input[value='tier:survival:survival-standard'][data-size='10235']"
    assert_select "input[value='tier:survival:survival-comprehensive'][data-size='14992']"
    assert_select "label[data-action='pointerdown->wizard#rememberRadio']", minimum: 1
    assert_select ".archive-storage-planner", count: 2
    assert_select "[data-wizard-storage-total-mb-value]"
    assert_select "[data-wizard-target='storageSelectionBar']", count: 2
    assert_select ".storage-selected", count: 2
    assert_select ".ai-setup-note", text: /queues its GGUF file/
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

  test "queues the selected tiny model during setup" do
    assert_enqueued_jobs 2, only: ContentDownloadJob do
      post setup_url, params: {
        capabilities: [ "information" ], wikipedia: "wikipedia:top-mini", packages: [], tiers: {},
        ai_profile: "smollm2-135m", theme: "dark"
      }
    end

    model = ContentDownload.find_by!(resource_id: "smollm2-135m")
    assert_equal "model", model.kind
    assert_equal "huggingface.co", URI(model.source_url).host
    assert_equal Rails.root.join("storage/models/smollm2-135m.gguf"), model.inferred_destination_path
  end

  test "requeues a model marked complete when its local file is missing" do
    model = ContentDownload.create!(resource_id: "smollm2-135m", title: "Old model",
      source_url: "https://huggingface.co/old.gguf", kind: "model", status: "complete",
      destination_path: "models/missing-model-test.gguf", downloaded_bytes: 100)

    assert_enqueued_with(job: ContentDownloadJob, args: [ model ]) do
      post setup_url, params: {
        capabilities: [ "information" ], wikipedia: "wikipedia:none", packages: [], tiers: {},
        ai_profile: "smollm2-135m", theme: "dark"
      }
    end

    model.reload
    assert_equal "queued", model.status
    assert_nil model.destination_path
    assert_equal 0, model.downloaded_bytes
  end
end
