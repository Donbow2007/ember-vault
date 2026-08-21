require "test_helper"

class SetupControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "renders curated global presets and custom packages" do
    get setup_url
    assert_response :success
    assert_select "title", text: "Setup — Ember Vault"
    assert_no_match(/Initial Setup/i, response.body)
    assert_select "h1", text: "Select maps by state."
    assert_no_match(/Choose your systems|Education Platform/, response.body)
    assert_select ".terms-document"
    assert_select "input[name='terms_accepted']:not([checked])"
    assert_select "button[data-wizard-target='next'][disabled]"
    assert_select "input[value='wikipedia:top-mini']"
    assert_select "input[name='knowledge_preset']", count: 3
    assert_select "input[name='knowledge_preset'][value='preset:suggested'][checked]"
    assert_select "input[value^='package:']", count: 23
    assert_select "select[data-map-selection-target='state'] option", count: 52
    assert_select "input[value='map-resource:arkansas'][data-size='400']"
    assert_select "input[value^='map-resource:']", count: 50
    assert_select ".religion-library", text: /OPTIONAL LIBRARY · NEVER INCLUDED IN TIERS/
    assert_select "input[name='religion[]']", count: 6
    assert_select "input[name='religion[]'][checked]", count: 0
    assert_select ".religion-options", text: /Christianity/
    assert_select ".religion-options", text: /Islam/
    assert_select ".religion-options", text: /Hindu traditions/
    assert_select ".religion-options", text: /Public domain in the USA/
    assert_select "input[name='ai_profile'][value='source-assistant'][checked]"
    assert_select "input[name='ai_profile'][value='smollm2-135m']"
    assert_select "input[name='ai_profile'][value='smollm2-360m']"
    assert_select "input[name='ai_profile'][value='llama3.2-1b']", count: 0
    assert_select "input[name='theme'][value='dark'][checked]"
    assert_select "input[name='theme'][value='light']"
    assert_select "input[type='radio'][data-action*='wizard#toggleRadio']", minimum: 1
    assert_select "input[value='preset:basic'][data-size='8']"
    assert_select "input[value='preset:suggested'][data-size='37']"
    assert_select "input[value='preset:comprehensive'][data-size='134']"
    assert_select ".medical-safety-notice", text: /NATURAL DOES NOT MEAN SAFE/
    assert_select ".evidence-label.historical", count: 2
    assert_select "input[value='package:cdc-safe-water-emergency']"
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
        terms_accepted: "1",
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
    acceptance = TermsAcceptance.find_by!(terms_version: TermsDocument.new.version)
    assert acceptance.accepted_at
    assert_equal TermsDocument.application_version, acceptance.application_version

    follow_redirect!
    assert_select "body[data-theme='light']"
    assert_select ".completion-page", text: /Theme: Light/
  end

  test "cannot complete initial setup without accepting current terms" do
    assert_no_difference([ "TermsAcceptance.count", "SetupConfiguration.count", "ContentDownload.count" ]) do
      post setup_url, params: {
        capabilities: [ "information" ], wikipedia: "wikipedia:none", packages: [],
        ai_profile: "disabled", theme: "dark"
      }
    end

    assert_redirected_to setup_url
    follow_redirect!
    assert_select ".setup-flash", text: /must read and accept/
  end

  test "does not prompt again after accepting the current version" do
    TermsAcceptance.accept_current!

    get setup_url

    assert_response :success
    assert_select ".terms-document", count: 0
    assert_select "input[name='terms_accepted']", count: 0
    assert_select ".wizard-steps button", count: 5
  end

  test "queues the selected tiny model during setup" do
    assert_enqueued_jobs 2, only: ContentDownloadJob do
      post setup_url, params: {
        terms_accepted: "1",
        capabilities: [ "information" ], wikipedia: "wikipedia:top-mini", packages: [], tiers: {},
        ai_profile: "smollm2-135m", theme: "dark"
      }
    end

    model = ContentDownload.find_by!(resource_id: "smollm2-135m")
    assert_equal "model", model.kind
    assert_equal "huggingface.co", URI(model.source_url).host
    assert_equal Rails.root.join("storage/models/smollm2-135m.gguf"), model.inferred_destination_path
  end

  test "queues only the individually selected state map" do
    assert_enqueued_jobs 1, only: ContentDownloadJob do
      post setup_url, params: {
        terms_accepted: "1",
        capabilities: [ "information" ], wikipedia: "wikipedia:none", packages: [ "map-resource:arkansas" ], tiers: {},
        ai_profile: "disabled", theme: "dark"
      }
    end

    map = ContentDownload.find_by!(resource_id: "arkansas")
    assert_equal "map", map.kind
    assert_equal 400.megabytes, map.expected_bytes
    assert_equal [ "map-resource:arkansas", "wikipedia:none" ], SetupConfiguration.last.selected_resources
    assert_nil ContentDownload.find_by(resource_id: "texas")
  end

  test "queues selected religious texts without adding unselected traditions" do
    assert_enqueued_jobs 2, only: ContentDownloadJob do
      post setup_url, params: {
        terms_accepted: "1",
        capabilities: [ "information" ], wikipedia: "wikipedia:none", packages: [], tiers: {},
        religion: [ "religion:religion-buddhism-dhammapada-muller", "religion:religion-taoism-tao-te-ching-legge" ],
        ai_profile: "disabled", theme: "dark"
      }
    end

    assert ContentDownload.exists?(resource_id: "religion-buddhism-dhammapada-muller", kind: "document")
    assert ContentDownload.exists?(resource_id: "religion-taoism-tao-te-ching-legge", kind: "document")
    assert_not ContentDownload.exists?(resource_id: "religion-christianity-kjv-1769")
    assert_equal 2, SetupConfiguration.last.selected_resources.grep(/^religion:/).length
  end

  test "queues an inherited curated preset without duplicate resources" do
    assert_enqueued_jobs 11, only: ContentDownloadJob do
      post setup_url, params: {
        terms_accepted: "1",
        capabilities: [ "information" ], knowledge_preset: "preset:suggested",
        packages: [ "package:cdc-safe-water-emergency" ], wikipedia: "wikipedia:none", religion: [],
        ai_profile: "disabled", theme: "dark"
      }
    end

    assert_equal 11, ContentDownload.where(kind: "document").count
    assert_equal 1, ContentDownload.where(resource_id: "cdc-safe-water-emergency").count
    assert_equal "preset:suggested", SetupConfiguration.last.selected_resources.find { |key| key.start_with?("preset:") }
  end

  test "refuses to start a selection larger than available storage" do
    metrics = Object.new
    metrics.define_singleton_method(:call) { { total: 100, used: 99, available: 1, percent: 99 } }
    original_constructor = StorageMetrics.method(:new)
    StorageMetrics.define_singleton_method(:new) { metrics }

    assert_no_enqueued_jobs do
      assert_no_difference([ "SetupConfiguration.count", "ContentDownload.count" ]) do
        post setup_url, params: {
          terms_accepted: "1",
          capabilities: [ "information" ], knowledge_preset: "preset:basic", packages: [],
          wikipedia: "wikipedia:none", religion: [], ai_profile: "disabled", theme: "dark"
        }
      end
    end

    assert_redirected_to setup_url
    follow_redirect!
    assert_select ".setup-flash", text: /Reduce the selection or free storage/
  ensure
    StorageMetrics.define_singleton_method(:new, original_constructor) if original_constructor
  end

  test "requeues a model marked complete when its local file is missing" do
    model = ContentDownload.create!(resource_id: "smollm2-135m", title: "Old model",
      source_url: "https://huggingface.co/old.gguf", kind: "model", status: "complete",
      destination_path: "models/missing-model-test.gguf", downloaded_bytes: 100)

    assert_enqueued_with(job: ContentDownloadJob, args: [ model ]) do
      post setup_url, params: {
        terms_accepted: "1",
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
