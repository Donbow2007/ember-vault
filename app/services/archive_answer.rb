class ArchiveAnswer
  Source = Data.define(:passage, :quote, :context)
  Result = Data.define(:question, :sources) do
    def found?
      sources.any?
    end
  end

  STOP_WORDS = %w[a an and are as at be by can could did do does for from how i in is it
    me of on or should that the this to was what when where which who why with would you your].to_set.freeze
  MAX_SOURCES = 5
  MAX_QUOTE_LENGTH = 520
  MAX_CONTEXT_LENGTH = 1_200
  MAX_PROCEDURE_LENGTH = 3_200
  PROCEDURE_WORDS = %w[how recipe make prepare cook bake ingredients directions instructions steps].freeze
  WATER_SAFETY_WORDS = %w[safe drink drinking purify purification disinfect disinfection treat treatment].freeze
  PROCEDURE_SECTION_PATTERN = /\A(?:purifying|treating|disinfecting)\b/i
  NOISE_PATTERNS = [ /:root\s*\{/i, /window\._WBWombatInit/i, /wombatSetup/i, /function\s*\(/i,
    /return\s+href\.toString/i, /const\s+current_url/i, /current_url\.substring/i ].freeze

  def initialize(question)
    @question = question.to_s.squish
  end

  def call
    return Result.new(question: @question, sources: []) if terms.empty?

    passages = retrieve_passages
    passages = passages.uniq { |passage| [ passage.document_id, passage.heading ] } if procedural?
    source_limit = water_safety_question? ? 2 : MAX_SOURCES
    sources = passages.first(source_limit).filter_map do |passage|
      quote = procedural? ? expanded_procedure(passage) : best_sentence(passage.body)
      Source.new(passage:, quote:, context: context_for(passage, quote)) if quote.present?
    end
    Result.new(question: @question, sources:)
  end

  private

  def terms
    @terms ||= @question.downcase.scan(/[[:alnum:]]{2,}/).reject { |term| STOP_WORDS.include?(term) }.uniq.first(8)
  end

  def retrieve_passages
    candidates = {}
    retrieval_queries.each_with_index do |query, query_index|
      Passage.search(query, limit: MAX_SOURCES * 3).each do |passage|
        candidates[passage.id] ||= [ passage, query_index ]
      end
    end

    if candidates.empty?
      terms.each do |term|
        Passage.search(term, limit: MAX_SOURCES).each { |passage| candidates[passage.id] ||= [ passage, 0 ] }
        break if candidates.size >= MAX_SOURCES * 2
      end
    end

    minimum_relevance = terms.size >= 3 ? 2 : 1
    candidates.values
      .select { |passage, query_index| query_index.positive? || relevance(searchable_text(passage)) >= minimum_relevance }
      .sort_by { |passage, query_index| -candidate_score(passage, query_index) }
      .map(&:first)
  end

  def retrieval_queries
    queries = [ terms.join(" ") ]
    queries << "water purification" if water_safety_question?
    queries
  end

  def searchable_text(passage)
    "#{passage.heading} #{passage.body}"
  end

  def candidate_score(passage, query_index)
    text = searchable_text(passage).downcase
    score = relevance(text) * 4
    score += 3 if query_index.zero?
    return score unless water_safety_question?

    score += 30 if text.match?(/purifying (?:water )?by boiling/)
    score += 18 if text.match?(/rolling boil|boiling is the best method/)
    score += 8 if text.include?("water purification")
    score -= 24 if text.match?(/what did we learn|ask one child|group discussion|school lesson/)
    score
  end

  def procedural?
    question_words = @question.downcase.scan(/[[:alpha:]]{2,}/)
    (question_words & PROCEDURE_WORDS).any?
  end

  def water_safety_question?
    words = @question.downcase.scan(/[[:alpha:]]+/)
    words.include?("water") && (words & WATER_SAFETY_WORDS).any?
  end

  def expanded_procedure(passage)
    section_start = procedure_section_heading?(passage.body)
    first_position = section_start ? passage.position : passage.position - 8
    last_position = passage.position + (section_start ? 30 : 12)
    related = passage.document.passages
      .where(position: first_position..last_position, heading: passage.heading)
      .order(:position)
      .reject { |candidate| noisy?(candidate.body) }
    if section_start
      related = related.each_with_index.take_while do |candidate, index|
        index.zero? || !procedure_section_heading?(candidate.body)
      end.map(&:first)
    end
    content = related.map { |candidate| clean_procedure_text(candidate.body, passage.heading) }.compact_blank.join("\n\n")
    content.truncate(MAX_PROCEDURE_LENGTH, separator: "\n")
  end

  def procedure_section_heading?(body)
    body.to_s.squish.match?(PROCEDURE_SECTION_PATTERN)
  end

  def context_for(passage, quote)
    return quote if procedural?

    related = passage.document.passages
      .where(position: (passage.position - 1)..(passage.position + 1))
      .order(:position)
      .reject { |candidate| noisy?(candidate.body) }
    content = related.map { |candidate| candidate.body.to_s.squish }.compact_blank.join("\n\n")
    content.truncate(MAX_CONTEXT_LENGTH, separator: " ").presence || quote
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
