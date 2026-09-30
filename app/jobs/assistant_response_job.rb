class AssistantResponseJob < ApplicationJob
  queue_as :ai

  def self.model_eligible?(_question)
    true
  end

  def perform(response)
    return if response.reload.cancelled? || response.complete?
    return mark_cancelled(response) if response.reload.cancel_requested?

    response.update!(status: "running", error_message: nil)
    retrieval = ArchiveAnswer.new(response.question).call
    source_ids = retrieval.sources.map { |source| source.passage.id }
    response.update!(source_passage_ids: source_ids)
    return mark_cancelled(response) if response.reload.cancel_requested?

    answer, mode, runtime_error = build_answer(response, retrieval.sources)

    return mark_cancelled(response) if response.reload.cancel_requested?

    response.update!(answer:, response_mode: mode,
      status: "complete", error_message: runtime_error)
  rescue LocalAiRuntime::CancelledError
    mark_cancelled(response)
  rescue StandardError => error
    response.update_columns(status: "failed", error_message: error.message, updated_at: Time.current)
    Rails.logger.error("Assistant response #{response.id} failed: #{error.class}: #{error.message}")
  end

  private

  def build_answer(response, sources)
    runtime = LocalAiRuntime.new
    fallback = -> {
      sources.any? ? SourceAnswerFormatter.new(question: response.question, sources:).call : AssistantPrompt::INSUFFICIENT_MESSAGE
    }
    return [ fallback.call, "source-assistant", nil ] unless runtime.available?

    prompt = AssistantPrompt.new(question: response.question, sources:)
    cancellation_check = -> { response.reload.cancel_requested? }
    [ runtime.generate(prompt, cancelled: cancellation_check), runtime.profile, nil ]
  rescue LocalAiRuntime::CancelledError
    raise
  rescue LocalAiRuntime::Error => error
    [ fallback.call, "source-assistant-fallback", error.message ]
  end

  def mark_cancelled(response)
    attributes = if response.answer.present?
      { status: "complete", response_mode: "source-assistant", error_message: "Local model refinement was stopped." }
    else
      { status: "cancelled", error_message: nil }
    end
    response.update_columns(**attributes, updated_at: Time.current)
  end
end
