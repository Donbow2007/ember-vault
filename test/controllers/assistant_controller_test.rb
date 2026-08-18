require "test_helper"

class AssistantControllerTest < ActionDispatch::IntegrationTest
  test "shows a cited local answer linked to its exact passage" do
    document = Document.create!(title: "Water Safety", original_filename: "water.txt", content_type: "text/plain",
      stored_path: "storage/archive_files/water.txt", byte_size: 100, status: "ready", passage_count: 1)
    passage = document.passages.create!(position: 0, heading: "Flood Water",
      body: "Boil clear water for one minute before drinking after a flood.")
    Passage.rebuild_search_index

    get assistant_url, params: { question: "How do I boil water after a flood?" }

    assert_response :success
    assert_select ".assistant-answer", text: /Boil clear water/
    assert_select "a[href='#{document_path(document, passage_id: passage.id, anchor: "passage-#{passage.id}")}']"
    assert_select ".assistant-answer", text: /CITED SOURCE EXTRACTION/
  end

  test "reports when no indexed source supports the question" do
    get assistant_url, params: { question: "repair a diesel generator" }

    assert_response :success
    assert_select ".assistant-answer", text: /I couldn’t find an answer/
  end
end
