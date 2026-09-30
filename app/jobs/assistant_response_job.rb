class AssistantResponseJob < ApplicationJob
  queue_as :ai

  def perform(response)
    return if response.reload.cancelled? || response.complete?
    return mark_cancelled(response) if response.cancel_requested?

    response.update!(status: "running", error_message: nil)
    runtime = LocalAiRuntime.new
    raise LocalAiRuntime::Error, "No local model is installed or available." unless runtime.available?

    prompt = AssistantPrompt.new(question: response.question, sources: [])
    answer = runtime.generate(prompt, cancelled: -> { response.reload.cancel_requested? })
    return mark_cancelled(response) if response.reload.cancel_requested?

    response.update!(answer:, response_mode: runtime.profile, status: "complete", error_message: nil)
  rescue LocalAiRuntime::CancelledError
    mark_cancelled(response)
  rescue StandardError => error
    response.update_columns(status: "failed", error_message: error.message.to_s.first(500), updated_at: Time.current)
    Rails.logger.error("Assistant response #{response.id} failed: #{error.class}: #{error.message}")
  end

  private

  def mark_cancelled(response)
    response.update_columns(status: "cancelled", error_message: nil, updated_at: Time.current)
  end
end
