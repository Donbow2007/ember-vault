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
    response.update!(status: response.queued? ? "cancelled" : "cancel_requested") if response.pending?
    redirect_to assistant_path(response_id: response.id)
  end

  private

  def answer_and_redirect(question)
    response = AssistantResponse.create!(
      question: question.first(500),
      answer: nil,
      response_mode: LocalAiRuntime.new.profile,
      status: "queued"
    )
    job = AssistantResponseJob.perform_later(response)
    response.update!(status: "failed", error_message: "Local AI could not be queued.") unless job.successfully_enqueued?
    redirect_to assistant_path(response_id: response.id)
  rescue ActiveJob::EnqueueError => error
    response&.update!(status: "failed", error_message: error.message)
    redirect_to assistant_path(response_id: response&.id), alert: "Local AI could not be started."
  end
end
