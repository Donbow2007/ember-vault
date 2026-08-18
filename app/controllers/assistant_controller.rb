class AssistantController < ApplicationController
  def show
    @question = params[:question].to_s.strip
    @answer = ArchiveAnswer.new(@question).call if @question.present?
    @configuration = SetupConfiguration.order(created_at: :desc).first
  end
end
