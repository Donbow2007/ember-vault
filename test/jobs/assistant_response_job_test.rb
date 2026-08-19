require "test_helper"

class AssistantResponseJobTest < ActiveJob::TestCase
  test "builds a cited fallback answer without a model runtime" do
    document = Document.create!(title: "Water Safety", original_filename: "water.txt", content_type: "text/plain",
      stored_path: "storage/archive_files/water.txt", byte_size: 100, status: "ready", passage_count: 1)
    passage = document.passages.create!(position: 0, heading: "Boiling",
      body: "Bring clear water to a rolling boil for one minute before drinking it.")
    Passage.rebuild_search_index
    response = AssistantResponse.create!(question: "How should I boil water?")

    AssistantResponseJob.perform_now(response)

    response.reload
    assert response.complete?
    assert_equal "source-assistant", response.response_mode
    assert_equal [ passage.id ], response.source_passage_ids
    assert_match(/rolling boil/, response.answer)
  end

  test "does not invent an answer when retrieval has no evidence" do
    response = AssistantResponse.create!(question: "How do I repair a fusion reactor?")

    AssistantResponseJob.perform_now(response)

    assert_equal AssistantPrompt::INSUFFICIENT_MESSAGE, response.reload.answer
    assert_empty response.source_passage_ids
  end

  test "does not start a response whose cancellation was requested while queued" do
    response = AssistantResponse.create!(question: "How do I store water?", status: "cancel_requested")

    AssistantResponseJob.perform_now(response)

    assert response.reload.cancelled?
    assert_nil response.answer
  end

  test "does not start an already cancelled response" do
    response = AssistantResponse.create!(question: "How do I store water?", status: "cancelled")

    AssistantResponseJob.perform_now(response)

    assert response.reload.cancelled?
    assert_nil response.answer
  end
end
