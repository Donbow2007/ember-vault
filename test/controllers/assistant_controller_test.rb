require "test_helper"

class AssistantControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "shows a cited local answer linked to its exact passage" do
    document = Document.create!(title: "Water Safety", original_filename: "water.txt", content_type: "text/plain",
      stored_path: "storage/archive_files/water.txt", byte_size: 100, status: "ready", passage_count: 1)
    passage = document.passages.create!(position: 0, heading: "Flood Water",
      body: "Boil clear water for one minute before drinking after a flood.")
    Passage.rebuild_search_index

    assert_no_enqueued_jobs do
      post assistant_url, params: { question: "How do I boil water after a flood?" }
    end

    assert_redirected_to assistant_url(response_id: AssistantResponse.last.id)
    assert AssistantResponse.last.complete?
    follow_redirect!
    assert_select ".assistant-answer", text: /Boil clear water/
    assert_select "a[href='#{document_path(document, passage_id: passage.id, anchor: "passage-#{passage.id}")}']"
    assert_select ".assistant-answer", text: /SOURCE ASSISTANT/
    assert_select "form[action='#{ai_profile_setting_path}'][data-controller='auto-submit'][data-action='change->auto-submit#submit']" do
      assert_select "select[name='ai_profile'] option[value='source-assistant']"
      assert_select "noscript input[type='submit'][value='SAVE']"
    end
    assert_select ".assistant-ai-panel", text: /Saves automatically when changed/
  end

  test "reports when no indexed source supports the question" do
    post assistant_url, params: { question: "repair a diesel generator" }

    follow_redirect!
    assert_response :success
    assert_select ".assistant-answer", text: /don't have enough information/
  end

  test "renders a locally polled pending response" do
    response = AssistantResponse.create!(question: "How do I store water?")
    get assistant_url(response_id: response.id)

    assert_select "[data-controller='assistant-response']"
    get assistant_response_url(response)
    assert_response :success
    assert_select "#assistant-response-#{response.id}", text: /Searching the local index/
    assert_select "form[action='#{cancel_assistant_response_path(response)}']"
  end

  test "immediately cancels a queued response" do
    response = AssistantResponse.create!(question: "How do I store water?")

    post cancel_assistant_response_url(response)

    assert_redirected_to assistant_url(response_id: response.id)
    assert response.reload.cancelled?
  end

  test "requests termination of a running response" do
    response = AssistantResponse.create!(question: "How do I store water?", status: "running")

    post cancel_assistant_response_url(response)

    assert_redirected_to assistant_url(response_id: response.id)
    assert response.reload.cancel_requested?
  end

  test "keeps an immediate source answer when queued model refinement is stopped" do
    response = AssistantResponse.create!(question: "What does the archive say?", answer: "Immediate guidance [1]", status: "queued")

    get assistant_url(response_id: response.id)
    assert_select ".assistant-generated-answer", text: /Immediate guidance/

    post cancel_assistant_response_url(response)

    assert response.reload.complete?
    assert_equal "Immediate guidance [1]", response.answer
  end
end
