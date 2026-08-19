require "test_helper"

class LocalAiRuntimeTest < ActiveSupport::TestCase
  test "caps local model work at four seconds" do
    assert_equal 4, LocalAiRuntime::MAX_TIMEOUT_SECONDS
    assert_operator LocalAiRuntime::TIMEOUT_SECONDS, :<=, 4
  end

  test "rejects unsupported numbers introduced by a model" do
    runtime = LocalAiRuntime.new(profile: "smollm2-360m")

    assert_not runtime.send(:grounded_output?, "Heat it to 350 degrees [1]", "Heat it to 100 degrees.")
    assert runtime.send(:grounded_output?, "Heat it to 100 degrees [1]", "Heat it to 100 degrees.")
  end

  test "keeps procedural and hazardous questions out of model inference" do
    job = AssistantResponseJob.new

    assert_not AssistantResponseJob.model_eligible?("How do I make shortbread?")
    assert_not AssistantResponseJob.model_eligible?("What medicine should treat this burn?")
    assert AssistantResponseJob.model_eligible?("What does the archive say about winter shelter?")
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
