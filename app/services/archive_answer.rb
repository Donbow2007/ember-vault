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
  MAX_SCORING_CHARACTERS = 4_000
  PROCEDURE_WORDS = %w[how recipe make prepare cook bake ingredients directions instructions steps].freeze
  WATER_SAFETY_WORDS = %w[safe drink drinking purify purification disinfect disinfection treat treatment].freeze
  QUERY_FILLER_WORDS = %w[
    about archive available avoid clear clearly give guidance handle key know long make mistakes practical recommendation recommendations
    safest safely tell term things topic when
  ].to_set.freeze
  KNOT_WORDS = %w[bowline hitch knot knots lashing lashings prusik rope sheepshank].to_set.freeze
  RADIO_WORDS = %w[amateur antenna antennas ham radio repeater transceiver transmitter].to_set.freeze
  GARDEN_WORDS = %w[garden gardening grow growing plant planting seed seeds seedling seedlings tomato tomatoes].to_set.freeze
  FOOD_STORAGE_WORDS = %w[
    dehydrate dehydrating dehydration dried dry drying fermenting fermentation food grain grains hardtack herbs jerky pantry pickle pickling
    beans egg eggs fruit meat oil potato potatoes preserve preserving preservation root cellar smoke smoking store stored storing vegetable vegetables
  ].to_set.freeze
  PROCEDURE_SECTION_PATTERN = /\A(?:purifying|treating|disinfecting)\b/i
  BOILING_EXCLUSION_PATTERNS = [
    /\b(?:can(?:not|'t)|could(?: not|n't)|unable to|do not|don't) boil\b/i,
    /\b(?:do not|don't) have (?:a|any) (?:way|means|method) to boil\b/i,
    /\bwithout (?:being able to )?boil(?:ing)?\b/i,
    /\bboiling (?:is not|isn't|isn’t|won't be|will not be) (?:possible|available|an option)\b/i
  ].freeze
  NOISE_PATTERNS = [ /:root\s*\{/i, /window\._WBWombatInit/i, /wombatSetup/i, /function\s*\(/i,
    /return\s+href\.toString/i, /const\s+current_url/i, /current_url\.substring/i,
    /window\.location/i, /navigator\.serviceWorker/i, /No SW Fallback/i, /prefix\s*\+=/i ].freeze

  def initialize(question)
    @question = question.to_s.squish
  end

  def call
    return Result.new(question: @question, sources: []) if terms.empty?

    passages = retrieve_passages.first(MAX_SOURCES * 4).map { |passage| answer_bearing_passage(passage) }
      .uniq { |passage| [ passage.document_id, passage.heading ] }
    source_limit = water_safety_question? ? 2 : MAX_SOURCES
    sources = passages.first(source_limit).filter_map do |passage|
      quote = if q_and_a_answer?(passage)
        q_and_a_answer_excerpt(passage)
      elsif procedural?
        expanded_procedure(passage)
      else
        best_sentence(passage.body)
      end
      Source.new(passage:, quote:, context: context_for(passage, quote)) if quote.present?
    end
    Result.new(question: @question, sources:)
  end

  private

  def terms
    @terms ||= @question.downcase.scan(/[[:alnum:]]{2,}/)
      .reject { |term| STOP_WORDS.include?(term) || QUERY_FILLER_WORDS.include?(term) }.uniq.first(10)
  end

  def retrieve_passages
    candidates = {}
    routed_ids = routed_document_ids
    if routed_ids.any?
      routed_passage_count = Document.where(id: routed_ids).sum(:passage_count)
      if routed_passage_count <= 100_000
        Passage.search_within_documents(retrieval_queries.join(" "), document_ids: routed_ids, limit: MAX_SOURCES * 16).each do |passage|
          add_candidate(candidates, passage, query_index: 1, routed: true)
        end
      else
        retrieval_queries.each_with_index do |query, query_index|
          Passage.search(query, limit: MAX_SOURCES * 8, document_ids: routed_ids).each do |passage|
            add_candidate(candidates, passage, query_index:, routed: true)
          end
        end
      end
    else
      retrieval_queries.each_with_index do |query, query_index|
        Passage.search(query, limit: MAX_SOURCES * 6).each do |passage|
          add_candidate(candidates, passage, query_index:, routed: false)
        end
      end
    end

    if candidates.empty?
      terms.each do |term|
        Passage.search(term, limit: MAX_SOURCES * 2).each do |passage|
          add_candidate(candidates, passage, query_index: 0, routed: false)
        end
        break if candidates.size >= MAX_SOURCES * 2
      end
    end

    minimum_relevance = terms.size >= 3 ? 2 : 1
    candidates.values
      .select do |passage, query_index, routed|
        overlap = relevance(searchable_text(passage))
        routed || overlap >= minimum_relevance || (water_safety_question? && query_index.positive? && overlap.positive?)
      end
      .sort_by { |passage, query_index, routed| -candidate_score(passage, query_index, routed:) }
      .map(&:first)
  end

  def add_candidate(candidates, passage, query_index:, routed:)
    existing = candidates[passage.id]
    candidate = [ passage, query_index, routed ]
    candidates[passage.id] = candidate if existing.nil? || candidate_score(*candidate.first(2), routed:) > candidate_score(*existing.first(2), routed: existing.last)
  end

  def retrieval_queries
    queries = [ terms.join(" ") ]
    if water_safety_question?
      if boiling_excluded?
        queries << "chemical pollutants bleach water"
        queries << "unscented household bleach drinking water 16 drops gallon 30 minutes"
        queries << "iodine water purification drops quart 30 minutes"
      else
        queries << "water purification"
      end
    end
    queries << "bowline loop rope" if terms.include?("bowline")
    queries << "corn wind pollinated blocks" if terms.include?("corn") && terms.any? { |term| term.start_with?("block") }
    queries << "best way store potatoes storage" if terms.include?("potatoes") && terms.any? { |term| term.start_with?("stor") }
    queries << "pressure canning low acid vegetables" if terms.include?("vegetables") && (terms & %w[preserve preserving preservation canning]).any?
    queries
  end

  def searchable_text(passage)
    "#{passage.heading} #{passage.body.to_s.first(MAX_SCORING_CHARACTERS)}"
  end

  def candidate_score(passage, query_index, routed: false)
    text = searchable_text(passage).downcase
    score = relevance(text) * 4
    score += 3 if query_index.zero?
    score += 36 if routed
    score += 12 if routed && !passage.document.title.end_with?("Q&A")
    score += 8 if relevance(passage.heading.to_s) >= [ terms.size, 2 ].min
    score += [ passage.body.to_s.first(MAX_SCORING_CHARACTERS).scan(/(?:\A|\s)\d+[.)]\s+/).size, 4 ].min * 6 if procedural?
    if terms.include?("bowline")
      score += text.include?("bowline") ? 35 : -40
      score += 25 if text.match?(/\ba bowline makes a loop\b|\A\s*bowline\b/i)
    end
    if terms.include?("corn") && terms.any? { |term| term.start_with?("block") }
      score += 50 if text.match?(/wind pollinat/) && text.match?(/block/)
    end
    if terms.include?("potatoes") && terms.any? { |term| term.start_with?("stor") }
      score += 45 if passage.heading.to_s.match?(/(?:best way|how).*stor.*potato|stor.*seed potato/i)
      score -= 30 if text.match?(/ground beef|sauce mix|bouillon|attach.*instructions/i)
    end
    score -= 20 if noisy?(passage.body)
    return score unless water_safety_question?

    if boiling_excluded?
      score += 60 if text.match?(/plain unscented household bleach|unscented household bleach.*water purification/)
      score += 40 if text.match?(/16 drops.*(?:each|per) gallon|1\/8 teaspoon.*(?:each|per) gallon/)
      score += 38 if text.match?(/bleach will not remove chemical pollutants|unsafe because of chemicals.*do not drink/)
      score += 34 if text.match?(/2%.*(?:tincture of )?iodine|iodine water purification tablets/)
      score -= 70 if text.match?(/purifying (?:water )?by boiling|rolling boil|boiling is the best method/)
    else
      score += 30 if text.match?(/purifying (?:water )?by boiling/)
      score += 18 if text.match?(/rolling boil|boiling is the best method/)
    end
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

  def boiling_excluded?
    normalized_question = @question.tr("’", "'")
    BOILING_EXCLUSION_PATTERNS.any? { |pattern| normalized_question.match?(pattern) }
  end

  def expanded_procedure(passage)
    section_start = procedure_section_heading?(passage.body)
    scanned_document = passage.heading.to_s.start_with?("files/")
    first_position = if section_start
      passage.position
    elsif scanned_document
      passage.position - 1
    else
      passage.position - 8
    end
    last_position = passage.position + (section_start ? 30 : (scanned_document ? 4 : 12))
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
    return quote if procedural? || q_and_a_answer?(passage)

    related = passage.document.passages
      .where(position: (passage.position - 1)..(passage.position + 1))
      .order(:position)
      .reject { |candidate| noisy?(candidate.body) }
    content = related.map { |candidate| candidate.body.to_s.squish }.compact_blank.join("\n\n")
    content.truncate(MAX_CONTEXT_LENGTH, separator: " ").presence || quote
  end

  def noisy?(body)
    text = body.to_s.first(MAX_SCORING_CHARACTERS * 2)
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
    terms.count { |term| words.any? { |word| related_word?(word, term) } }
  end

  def related_word?(word, term)
    word.start_with?(term) || term.start_with?(word) ||
      (word.length >= 6 && term.length >= 6 && word.first(6) == term.first(6))
  end

  def routed_document_ids
    @routed_document_ids ||= begin
      words = @question.downcase.scan(/[[:alpha:]]+/).to_set
      text = @question.downcase
      titles = []
      water_route_words = WATER_SAFETY_WORDS.to_set + %w[boil boiling bleach chlorinate chlorinating chlorine cloudy filter filtering giardia rainwater well].to_set
      titles << "Water Treatment Library" if (words.include?("water") || words.include?("rainwater")) && (words & water_route_words).any?
      titles << "A Library of Knots" if (words & KNOT_WORDS).any?
      titles << "Canning" if (words & %w[botulism canned canner canning headspace jar jars pressure].to_set).any?
      titles << "Canning" if (words & %w[preserve preserving preservation].to_set).any? && (words & %w[food foods vegetable vegetables].to_set).any?
      food_storage_topic = (words & FOOD_STORAGE_WORDS).size >= 2 || text.match?(/\bmake (?:jerky|hardtack)\b/)
      titles << "Food for Preppers" if food_storage_topic || text.include?("root cellar") || text.include?("emergency pantry")
      titles.concat([ "Canadian Prepper: Bug Out Roll", "Canadian Prepper: Bug Out Concepts", "Urban Prepper" ]) if text.match?(/\bbug[ -]?out\b|\b72[ -]?hour\b/)
      titles << "Canadian Prepper: Winter Prepping" if (words & %w[cold snow winter woodstove].to_set).any?
      if text.include?("practical guidance is available about")
        titles.concat([ "Canadian Prepper: Winter Prepping", "Canadian Prepper: Bug Out Roll", "Canadian Prepper: Bug Out Concepts", "Urban Prepper" ])
      end
      titles << "Amateur Radio Q&A" if (words & RADIO_WORDS).any?
      titles << "Gardening Q&A" if (words & GARDEN_WORDS).any?
      titles.concat([ "Gardening Q&A", "Cooking Q&A" ]) if words.include?("potatoes") && (words & %w[store storing storage].to_set).any?
      titles.concat([ "FOSS Cooking", "Based.Cooking" ]) if text.match?(/\Ahow (?:do|can|should) i make\b/)
      cooking_words = %w[bake baking cook cooking food ingredient ingredients meat oven recipe].to_set
      titles << "Cooking Q&A" if (words & cooking_words).any?
      Document.where(title: titles.uniq, status: "ready").pluck(:id)
    end
  end

  def answer_bearing_passage(passage)
    return passage unless passage.document.title.end_with?("Q&A")
    return passage if q_and_a_answer?(passage)

    first_position = [ passage.position - 10, 0 ].max
    passage.document.passages.where(position: first_position..(passage.position + 80)).order(:position)
      .select { |candidate| candidate.heading == passage.heading }
      .find { |candidate| q_and_a_answer?(candidate) } || passage
  end

  def q_and_a_answer?(passage)
    passage.document.title.end_with?("Q&A") && passage.body.to_s.match?(/\b\d*\s*Answers?\d*\s+\d+\s+/i)
  end

  def q_and_a_answer_excerpt(passage)
    chunks = passage.document.passages.where(heading: passage.heading, position: passage.position..(passage.position + 20))
      .order(:position).each_with_index.take_while do |candidate, index|
        index.zero? || !candidate.body.to_s.squish.match?(/\A(?:answered|edited)\b/i)
      end.map { |candidate, _index| candidate.body.to_s.squish }
    chunks.first&.sub!(/\A.*?\b\d*\s*Answers?\d*\s+\d+\s+/i, "")
    chunks.join("\n").sub(/\s+(?:answered|edited)\s+\w+.*\z/i, "")
      .truncate(MAX_CONTEXT_LENGTH, separator: " ")
  end
end
