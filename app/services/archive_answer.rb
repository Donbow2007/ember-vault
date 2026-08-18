class ArchiveAnswer
  Source = Data.define(:passage, :quote)
  Result = Data.define(:question, :sources) do
    def found?
      sources.any?
    end
  end

  STOP_WORDS = %w[a an and are as at be by can could did do does for from how i in is it
    me of on or should that the this to was what when where which who why with would you your].to_set.freeze
  MAX_SOURCES = 5
  MAX_QUOTE_LENGTH = 520
  MAX_PROCEDURE_LENGTH = 3_200
  PROCEDURE_WORDS = %w[how recipe make prepare cook bake ingredients directions instructions steps].freeze
  NOISE_PATTERNS = [ /:root\s*\{/i, /window\._WBWombatInit/i, /wombatSetup/i, /function\s*\(/i,
    /return\s+href\.toString/i, /const\s+current_url/i, /current_url\.substring/i ].freeze

  def initialize(question)
    @question = question.to_s.squish
  end

  def call
    return Result.new(question: @question, sources: []) if terms.empty?

    passages = retrieve_passages
    passages = passages.uniq { |passage| [ passage.document_id, passage.heading ] } if procedural?
    sources = passages.first(MAX_SOURCES).filter_map do |passage|
      quote = procedural? ? expanded_procedure(passage) : best_sentence(passage.body)
      Source.new(passage:, quote:) if quote.present?
    end
    Result.new(question: @question, sources:)
  end

  private

  def terms
    @terms ||= @question.downcase.scan(/[[:alnum:]]{2,}/).reject { |term| STOP_WORDS.include?(term) }.uniq.first(8)
  end

  def retrieve_passages
    exact = Passage.search(terms.join(" "), limit: MAX_SOURCES).to_a
    return exact if exact.any?

    seen = {}
    terms.each do |term|
      Passage.search(term, limit: MAX_SOURCES).each { |passage| seen[passage.id] ||= passage }
      break if seen.size >= MAX_SOURCES * 2
    end
    minimum_relevance = terms.size >= 3 ? 2 : 1
    seen.values.select { |passage| relevance("#{passage.heading} #{passage.body}") >= minimum_relevance }
      .sort_by { |passage| -relevance("#{passage.heading} #{passage.body}") }
  end

  def procedural?
    question_words = @question.downcase.scan(/[[:alpha:]]{2,}/)
    (question_words & PROCEDURE_WORDS).any?
  end

  def expanded_procedure(passage)
    related = passage.document.passages
      .where(position: (passage.position - 8)..(passage.position + 12), heading: passage.heading)
      .order(:position)
      .reject { |candidate| noisy?(candidate.body) }
    content = related.map { |candidate| clean_procedure_text(candidate.body, passage.heading) }.compact_blank.join("\n\n")
    content.truncate(MAX_PROCEDURE_LENGTH, separator: "\n")
  end

  def noisy?(body)
    text = body.to_s
    NOISE_PATTERNS.any? { |pattern| text.match?(pattern) }
  end

  def clean_procedure_text(body, heading)
    body.to_s.gsub(/\A#{Regexp.escape(heading)}\s+(?:Home|Author|Back)(?:\s+(?:Home|Author|Back))*\s*/i, "")
      .sub(/\s+Tags\s+.*\z/m, "")
      .sub(/\s+Problems with the site\?.*\z/m, "")
      .strip
  end

  def best_sentence(body)
    candidates = body.to_s.squish.split(/(?<=[.!?])\s+|\n+/).filter_map do |sentence|
      clean = sentence.squish
      next if clean.length < 25

      [ clean, relevance(clean) ]
    end
    sentence = candidates.max_by { |candidate, score| [ score, [ candidate.length, MAX_QUOTE_LENGTH ].min ] }&.first
    sentence ||= body.to_s.squish
    sentence.truncate(MAX_QUOTE_LENGTH, separator: " ")
  end

  def relevance(sentence)
    words = sentence.downcase.scan(/[[:alnum:]]{2,}/)
    terms.count { |term| words.any? { |word| word.start_with?(term) || term.start_with?(word) } }
  end
end
