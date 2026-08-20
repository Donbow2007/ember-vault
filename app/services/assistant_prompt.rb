class AssistantPrompt
  # Keep the complete prompt plus generation headroom inside the Pi profile's
  # 1,024-token context window. Retrieval may retain more sources for the UI,
  # but the model receives only the highest-ranked useful excerpts.
  MAX_CONTEXT_CHARACTERS = 520
  MAX_MODEL_SOURCES = 1
  QUESTION_STOP_WORDS = %w[a an and are as at be by can do for from how i in is it of on or should that the this to
    was what when where which with you your].to_set.freeze
  INSUFFICIENT_MESSAGE = "I don't have enough information in the local archive to answer that safely."

  SYSTEM_INSTRUCTION = <<~TEXT.squish.freeze
    You are Ember, a calm offline field-guide companion. Sound like an experienced older brother:
    natural, direct, steady, and never corporate or theatrical. Answer only from SOURCE, in your own
    words, without mentioning search results. Keep simple answers brief; use steps or cautions when
    useful. Never add facts or fill gaps. Cite claims with [1], [2], and so on. If SOURCE is inadequate,
    say: #{INSUFFICIENT_MESSAGE}
  TEXT

  def initialize(question:, sources:)
    @question = question.to_s.squish
    @sources = sources
  end

  def system_instruction
    SYSTEM_INSTRUCTION
  end

  def source_count
    @sources.size
  end

  attr_reader :question

  def source_text
    model_source_pairs.map { |source, _index| source.context }.join(" ")
  end

  def primary_citation
    model_source_pairs.first&.last&.+(1)
  end

  def citation_for(answer)
    answer_words = meaningful_words(answer)
    source, index = model_source_pairs.max_by do |candidate, candidate_index|
      [ overlap(answer_words, meaningful_words(candidate.context)), -candidate_index ]
    end
    index + 1 if source && overlap(answer_words, meaningful_words(source.context)).positive?
  end

  def user_prompt
    <<~TEXT
      Question:
      #{@question}

      Format:
      #{response_shape}

      Sources:
      #{bounded_context}

      Using SOURCE only, answer now in a natural, practical voice. Do not repeat the question, role, or source text.
    TEXT
  end

  def completion_prompt
    <<~TEXT
      <|im_start|>system
      #{system_instruction}<|im_end|>
      <|im_start|>user
      #{user_prompt}<|im_end|>
      <|im_start|>assistant
    TEXT
  end

  private

  def response_shape
    words = @question.downcase.scan(/[[:alpha:]]+/)
    source_words = @sources.flat_map { |source| source.context.to_s.downcase.scan(/[[:alpha:]]+/) }
    if (words & %w[recipe cook bake ingredients meal food]).any? || (source_words & %w[ingredients servings]).any?
      "Give a short overview, then INGREDIENTS, METHOD, TIMING, and any source-supported cautions."
    elsif (words & %w[how repair build make prepare treat steps instructions]).any?
      "Give a direct overview, then MATERIALS OR REQUIREMENTS, numbered STEPS, and source-supported cautions."
    else
      "Answer directly in no more than two complete sentences."
    end
  end

  def bounded_context
    remaining = MAX_CONTEXT_CHARACTERS
    excerpts = []

    model_source_pairs.each do |source, original_index|
      index = original_index
      header = "[#{index + 1}] #{source.passage.document.title} — #{source.passage.heading}\n"
      break if remaining <= header.length + 80

      body = useful_excerpt(source, remaining - header.length)
      excerpts << "#{header}#{body}"
      remaining -= header.length + body.length
    end

    excerpts.join("\n\n")
  end

  def ranked_sources
    terms = meaningful_words(@question)
    @sources.each_with_index.sort_by do |source, index|
      heading_score = overlap(terms, meaningful_words(source.passage.heading)) * 3
      context_score = overlap(terms, meaningful_words(source.context))
      retrieval_priority = index.zero? ? 4 : 0
      [ -(heading_score + context_score + retrieval_priority), index ]
    end
  end

  def model_source_pairs
    @model_source_pairs ||= ranked_sources.first(MAX_MODEL_SOURCES)
  end

  def useful_excerpt(source, limit)
    terms = meaningful_words(@question)
    chunks = source.context.to_s.gsub(/\r\n?/, "\n").lines.flat_map do |line|
      line.squish.split(/(?<=[.!?])\s+/)
    end.each_with_index.filter_map do |chunk, index|
      clean = chunk.squish
      next if clean.length < 18 || clean.match?(/\A(?:asked|answered|edited|home|questions?|answers?\d*)\b/i)
      next if clean.match?(/(?:window\.|function\s*\(|background-image|serviceWorker|&nbsp;)/i)

      [ clean, index, overlap(terms, meaningful_words(clean)) ]
    end
    selected = chunks.sort_by { |chunk, index, score| [ -score, index, chunk.length ] }.first(3).map(&:first)
    excerpt = selected.join(" ").truncate(limit, separator: " ")
    excerpt.presence || source.quote.to_s.squish.truncate(limit, separator: " ")
  end

  def meaningful_words(text)
    text.to_s.downcase.scan(/[[:alnum:]]{3,}/).reject { |word| QUESTION_STOP_WORDS.include?(word) }.to_set
  end

  def overlap(first, second)
    (first & second).size
  end
end
