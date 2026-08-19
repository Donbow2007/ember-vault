class AssistantController < ApplicationController
  def show
    if params[:response_id].present?
      @response = AssistantResponse.find(params[:response_id])
      @question = @response.question
    else
      @question = params[:question].to_s.strip
      return answer_and_redirect(@question) if @question.present?
    end
    @configuration = SetupConfiguration.order(created_at: :desc).first
  end

  def create
    question = params[:question].to_s.strip
    return redirect_to(assistant_path, alert: "Enter a question first.") if question.blank?

    answer_and_redirect(question)
  end

  def status
    @response = AssistantResponse.find(params[:id])
    render partial: "response", locals: { response: @response }
  end

  def cancel
    response = AssistantResponse.find(params[:id])
    if response.pending?
      status = response.answer.present? && response.queued? ? "complete" : (response.queued? ? "cancelled" : "cancel_requested")
      response.update!(status:)
    end
    redirect_to assistant_path(response_id: response.id)
  end

  private

  def answer_and_redirect(question)
    question = question.first(500)
    retrieval = ArchiveAnswer.new(question).call
    answer = if retrieval.found?
      SourceAnswerFormatter.new(question:, sources: retrieval.sources).call
    else
      AssistantPrompt::INSUFFICIENT_MESSAGE
    end
    response = AssistantResponse.create!(question:, answer:,
      source_passage_ids: retrieval.sources.map { |source| source.passage.id },
      response_mode: "source-assistant", status: "complete")
    enqueue_model_enhancement(response) if retrieval.found?
    redirect_to assistant_path(response_id: response.id)
  end

  def enqueue_model_enhancement(response)
    return unless LocalAiRuntime.new.available? && AssistantResponseJob.model_eligible?(response.question)

    response.update!(status: "queued")
    job = AssistantResponseJob.perform_later(response)
    response.update!(status: "complete", error_message: "Local refinement could not be queued.") unless job.successfully_enqueued?
  rescue ActiveJob::EnqueueError => error
    response.update!(status: "complete", error_message: error.message)
  end
end
