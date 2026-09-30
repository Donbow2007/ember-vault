class AssistantPrompt
  attr_reader :question

  def initialize(question:, **)
    @question = question.to_s.squish
  end
end
