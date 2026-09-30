class AssistantPrompt
  def initialize(question:, sources: nil)
    @question = question.to_s.squish
  end

  def completion_prompt
    <<~TEXT
      <|im_start|>system
      You are Ember, a calm offline survival and field-guide companion. Answer directly and practically.
      Prefer concise, field-ready instructions. Clearly state uncertainty when missing details could
      materially affect safety. Do not claim to have searched documents, archives, or the internet.<|im_end|>
      <|im_start|>user
      #{@question}<|im_end|>
      <|im_start|>assistant
    TEXT
  end

  def source_count
    0
  end

  def source_text
    ""
  end
end
