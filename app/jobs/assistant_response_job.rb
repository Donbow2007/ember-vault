class AssistantResponseJob < ApplicationJob
  queue_as :ai

  def self.model_eligible?(question, answer: nil)
    words = question.downcase.scan(/[[:alpha:]]+/)
    hazardous = (words & %w[medical medicine dose dosage wound burn electrical chemical poison poisoning]).any?
    emergency_water = words.include?("water") && (words & %w[safe drink drinking purify disinfect treat]).any?
    food_preservation = (words & %w[botulism canning preserve preserving preservation]).any?
    food_storage = (words & %w[store storing storage]).any? &&
      (words & %w[beans egg eggs food grain grains meat oil potato potatoes vegetable vegetables]).any?
    structured_answer = answer.to_s.match?(/What you’ll need:|Here’s how to make it:|(?:\A|\n)\d+\.\s/)
    !hazardous && !emergency_water && !food_preservation && !food_storage && !structured_answer
  end

  def perform(response)
    return if response.reload.cancelled? || response.complete?
    return mark_cancelled(response) if response.reload.cancel_requested?

    response.update!(status: "running", error_message: nil)
    retrieval = ArchiveAnswer.new(response.question).call
    source_ids = retrieval.sources.map { |source| source.passage.id }
    response.update!(source_passage_ids: source_ids)
    return mark_cancelled(response) if response.reload.cancel_requested?

    if retrieval.found?
      answer, mode, runtime_error = build_answer(response, retrieval.sources)
    else
      answer = AssistantPrompt::INSUFFICIENT_MESSAGE
      mode = "source-assistant"
      runtime_error = nil
    end

    return mark_cancelled(response) if response.reload.cancel_requested?

    response.update!(answer:, response_mode: mode,
      source_passage_ids: SourceAnswerFormatter.cited_passage_ids(answer, retrieval.sources),
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
    fallback = -> { SourceAnswerFormatter.new(question: response.question, sources:).call }
    return [ fallback.call, "source-assistant", nil ] unless runtime.available? && self.class.model_eligible?(response.question)

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
