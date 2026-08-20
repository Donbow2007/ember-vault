require "test_helper"

class LocalAiRuntimeTest < ActiveSupport::TestCase
  test "caps local model work at five seconds" do
    assert_equal 5, LocalAiRuntime::MAX_TIMEOUT_SECONDS
    assert_operator LocalAiRuntime::TIMEOUT_SECONDS, :<=, 5
  end

  test "rejects unsupported numbers introduced by a model" do
    runtime = LocalAiRuntime.new(profile: "smollm2-360m")

    assert_not runtime.send(:grounded_output?, "Heat it to 350 degrees [1]", "Heat it to 100 degrees.")
    assert runtime.send(:grounded_output?, "Heat it to 100 degrees [1]", "Heat it to 100 degrees.")
  end

  test "rejects an insufficient answer that continues with unsupported advice" do
    document = Document.create!(title: "Guide", original_filename: "guide.txt", content_type: "text/plain",
      stored_path: "archive_files/guide.txt", byte_size: 10, status: "ready", passage_count: 1)
    passage = document.passages.create!(position: 0, heading: "Corn", body: "Corn is wind pollinated.")
    source = ArchiveAnswer::Source.new(passage:, quote: passage.body, context: passage.body)
    prompt = AssistantPrompt.new(question: "Why plant corn in blocks?", sources: [ source ])
    output = "#{AssistantPrompt::INSUFFICIENT_MESSAGE} Plant it in rows instead. [1]"

    assert LocalAiRuntime.new.send(:unusable_output?, output, prompt)
  end

  test "keeps complete model sentences and removes a truncated tail" do
    runtime = LocalAiRuntime.new
    output = "Plant corn in blocks for better wind pollination. This unfinished sentence"

    assert_equal "Plant corn in blocks for better wind pollination.", runtime.send(:trim_incomplete_tail, output)
    assert_equal "", runtime.send(:trim_incomplete_tail, "No finished sentence")
  end

  test "allows grounded practical questions but keeps hazardous ones out of model inference" do
    assert AssistantResponseJob.model_eligible?("How do I make shortbread?")
    assert AssistantResponseJob.model_eligible?("How do I make a bow drill?")
    assert_not AssistantResponseJob.model_eligible?("How do I make shortbread?", answer: "1. Mix the dough.\n2. Bake it.")
    assert_not AssistantResponseJob.model_eligible?("What medicine should treat this burn?")
    assert_not AssistantResponseJob.model_eligible?("How do I make water safe to drink?")
    assert_not AssistantResponseJob.model_eligible?("How does pressure canning preserve vegetables?")
    assert AssistantResponseJob.model_eligible?("What does the archive say about winter shelter?")
  end

  test "rejects a grounded response that skips the question's focus" do
    runtime = LocalAiRuntime.new

    assert_not runtime.send(:question_focused?,
      "Emergency ham radio operators should choose a memorable call sign.",
      "What antenna should I use for emergency ham radio?")
    assert runtime.send(:question_focused?,
      "A dipole antenna can be used for emergency ham radio.",
      "What antenna should I use for emergency ham radio?")
  end

  test "terminates a subprocess when cancellation is requested" do
    runtime = LocalAiRuntime.new
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    assert_raises(LocalAiRuntime::CancelledError) do
      runtime.send(:capture, [ RbConfig.ruby, "-e", "sleep 10" ], cancelled: -> { true })
    end

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
    assert_operator elapsed, :<, 3
  end
end
