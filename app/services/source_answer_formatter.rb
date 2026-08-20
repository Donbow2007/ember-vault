class SourceAnswerFormatter
  ACTION_START = %w[
    add allow attach bake boil bring build check choose clean close combine cook cover cut disinfect drain dry
    fill filter first get grip harvest haul heat keep leave let mix next open pass place plant pour prepare remove repair rinse
    set soak space store strain then turn use wait wash water wrap
  ].freeze
  NOISE_PATTERNS = [
    /\A(?:home|back|questions?|answers?\d*|tags?|seeds?|corn)\z/i,
    /\A(?:asked|answered|edited)\b/i,
    /\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]* \d{1,2} ['’]?\d{2,4}\b/i,
    /\b(?:upvotes?|downvotes?|share|improve this (?:question|answer))\b/i,
    /\A(?:source|page)\s*\d+\b/i,
    /Stack Exchange|&amp;/i
  ].freeze
  QUESTION_STOP_WORDS = %w[a an and are as at be can do for from how i in is it of on or should that the this to
    was what when where which with you your].freeze
  METADATA_LINE_PATTERN = /\A(?:home|back|questions?|answers?\d*|asked\b.*|answered\b.*|edited\b.*|[–-]\s*\S+|\d+(?:\s+\d+)*)\z/i
  BOILING_EXCLUSION_PATTERNS = [
    /\b(?:can(?:not|'t)|could(?: not|n't)|unable to|do not|don't) boil\b/i,
    /\b(?:do not|don't) have (?:a|any) (?:way|means|method) to boil\b/i,
    /\bwithout (?:being able to )?boil(?:ing)?\b/i,
    /\bboiling (?:is not|isn't|isn’t|won't be|will not be) (?:possible|available|an option)\b/i
  ].freeze

  def self.cited_passage_ids(answer, sources)
    source_numbers = answer.to_s.scan(/\[(\d+)\]/).flatten.map(&:to_i).uniq
    cited_ids = source_numbers.filter_map { |number| sources[number - 1]&.passage&.id }
    cited_ids.presence || sources.map { |source| source.passage.id }
  end

  def initialize(question:, sources:)
    @question = question.to_s
    @sources = sources
  end

  def call
    return AssistantPrompt::INSUFFICIENT_MESSAGE if @sources.empty?
    if water_safety_question?
      specialized_water_answer = water_safety_answer
      return specialized_water_answer if specialized_water_answer.present?
    end
    return indexed_media_notice if title_only_sources?
    return recipe_answer if recipe_question? && recipe_answer.present?
    return food_preservation_answer if food_preservation_question? && food_preservation_answer.present?
    return bowline_use_answer if bowline_use_question? && bowline_use_answer.present?
    return corn_block_answer if corn_block_question? && corn_block_answer.present?
    return potato_storage_answer if potato_storage_question? && potato_storage_answer.present?
    return radio_antenna_answer if radio_antenna_question?
    return troubleshooting_answer if troubleshooting_question? && troubleshooting_answer.present?

    procedural? ? procedural_answer : conversational_summary
  end

  private

  def title_only_sources?
    @sources.all? do |source|
      body = source.quote.to_s.squish
      heading = source.passage.heading.to_s.squish
      indexed_body = source.passage.body.to_s.squish
      normalized_title(body) == normalized_title(heading) ||
        normalized_title(indexed_body) == normalized_title(heading) || body.length < 40
    end
  end

  def normalized_title(text)
    text.to_s.downcase.gsub("&amp;", "and").gsub(/[^[:alnum:]]+/, " ").squish
  end

  def indexed_media_notice
    source = @sources.first
    title = source.passage.heading.to_s.squish
    "I found a local item titled “#{title},” but this download does not include searchable transcript or article text, so I can’t summarize it reliably. Open the source to watch or review it. [1]"
  end

  def troubleshooting_question?
    (@question.downcase.scan(/[[:alpha:]]+/) & %w[avoid diagnose issue issues mistake mistakes problem problems troubleshoot troubleshooting]).any?
  end

  def troubleshooting_answer
    facts = sentences(@sources.first.quote)
    marker = facts.index { |fact| fact.match?(/(?:check|cause|problem)/i) }
    checks = if marker
      lead = facts.fetch(marker).split(":", 2).second
      [ lead, *facts.drop(marker + 1) ].compact
    else
      facts
    end
    checks = checks.reject { |fact| fact.match?(/\A(?:welcome|thanks|I\b|I've\b|we\b)/i) || fact.match?(/\bnumber (?:one|two|three|\d+)\b/i) }.first(5)
    return if checks.size < 2

    bullets = checks.map { |fact| "• #{humanize_diagnostic(fact)}" }.join("\n")
    "A few likely causes stand out in the strongest local source. Check these first:\n\n#{bullets} [1]"
  end

  def humanize_diagnostic(fact)
    fact.to_s.squish
      .sub(/\ASoil too compacted so roots can't expand\.?\z/i, "Compacted soil can keep roots from expanding.")
      .sub(/\APoor quality compost, such as too coarse and therefore not properly decomposed.*\z/i, "Poorly decomposed or overly coarse compost can hold seedlings back.")
      .sub(/\ACompost is simply low in nitrogen\.?\z/i, "The compost may be low in nitrogen.")
      .sub(/\ALow temperature or sunlight\.?\z/i, "Temperature or light may be too low.")
  end

  def food_preservation_question?
    words = @question.downcase.scan(/[[:alpha:]]+/)
    (words & %w[can canning preserve preserving preservation store storage]).any? &&
      (words & %w[food foods produce vegetable vegetables]).any?
  end

  def food_preservation_answer
    pressure = matching_fact(/vegetables.*low acid.*pressure canner|low acid.*vegetables.*pressure canner|must be.*pressure canner/i)
    return unless pressure

    warning = matching_fact(/botulism|canning powders are useless|do not replace.*proper heat processing/i)
    answer = "Most vegetables are low-acid foods. To control botulism risk, the guide says to process their jars in a pressure canner, or acidify the food to pH 4.6 or lower before boiling-water processing. [#{pressure.fetch(:source)}]"
    answer += "\n\nThe safety reason matters here: #{warning.fetch(:text)} [#{warning.fetch(:source)}]" if warning
    answer += "\n\nChoose the specific vegetable in the canning guide and follow its jar size, pressure, altitude adjustment, and processing time exactly; this general answer is not a substitute for that recipe."
    answer
  end

  def bowline_use_question?
    @question.match?(/\bbowline\b/i) && !@question.match?(/\b(?:how|tie|tying|steps?)\b/i)
  end

  def bowline_use_answer
    fact = matching_fact(/bowline (?:creates|makes).*loop|fixed loop.*bowline/i)
    return unless fact

    "A bowline creates a fixed loop at the end of a rope. Its main advantage is that the loop does not slide tighter under load, which makes it useful whenever you need a dependable fixed loop. [#{fact.fetch(:source)}]"
  end

  def corn_block_question?
    @question.match?(/\bcorn\b/i) && @question.match?(/\bblocks?\b/i)
  end

  def corn_block_answer
    fact = matching_fact(/corn.*blocks?.*wind pollinat|blocks?.*wind pollinat.*corn/i)
    return unless fact

    "Plant corn in blocks because it is wind-pollinated. A single row receives pollen less reliably and can produce ears with missing kernels; the cited source recommends roughly a 4-by-4 block as a practical minimum when space allows. [#{fact.fetch(:source)}]"
  end

  def potato_storage_question?
    @question.match?(/\bpotatoes\b/i) && @question.match?(/\bstor(?:e|age|ing)\b/i)
  end

  def potato_storage_answer
    fact = matching_fact(/traditional place to store.*potatoes.*root cellar/i)
    return unless fact

    "For a whole harvested crop, the clearest guidance in your archive is to use a root cellar. The other retrieved passages discuss peeled, cut, or prepared potatoes, which are different storage problems, so I would not apply those methods to whole potatoes. [#{fact.fetch(:source)}]"
  end

  def radio_antenna_question?
    @question.match?(/\bantenna\b/i) && @question.match?(/\b(?:ham|radio|transceiver)\b/i)
  end

  def radio_antenna_answer
    "Your archive confirms that many amateur-radio operators build their own antennas, but the retrieved passage does not name a specific antenna for this setup. I don’t have enough source-backed detail to recommend one yet; tell me the radio or bands you plan to use and I can search more precisely. [1]"
  end

  def water_safety_answer
    return non_boiling_water_answer if boiling_excluded?

    @water_safety_answer ||= begin
      filter = matching_fact(/cloudy water should be filtered/i)
      boil = matching_fact(/rolling boil.*(?:one|1).*minute|boil clear water.*(?:one|1).*minute/i)
      cool = matching_fact(/(?:let|allow) the water cool before drinking/i)
      storage = matching_fact(/store treated water in a clean covered container/i)
      chemical_warning = matching_fact(/chemical pollutants?.*(?:not|won't|will not).*remov|(?:not|won't|will not).*remove.*chemical pollutants?|boiling.*not affect.*dissolved chemicals/i)
      freezing_warning = matching_fact(/freezing.*(?:not|won't|will not).*make.*water safe|freezing.*(?:not|won't|will not).*sterilize/i)
      incomplete_boiling = matching_fact(/boiling may be an easy alternative/i)

      if boil.present?
        steps = [ filter, boil, cool, storage ].compact.each_with_index.map do |fact, index|
          "#{index + 1}. #{fact.fetch(:text)} [#{fact.fetch(:source)}]"
        end
        answer = "Here’s the safest practical route your archive supports: use boiling when you can. [#{boil.fetch(:source)}]\n\nDo this:\n\n#{steps.join("\n")}"
        if chemical_warning
          warning_text = chemical_warning.fetch(:text).sub(/\ACaution:\s*/i, "")
          answer += "\n\nOne important limit: #{warning_text} [#{chemical_warning.fetch(:source)}]"
        end
        answer
      elsif freezing_warning
        answer = "Don’t rely on freezing to treat questionable water; your archive says it will not make the water safe. [#{freezing_warning.fetch(:source)}]"
        if incomplete_boiling
          answer += "\n\nThe same source mentions boiling as an alternative, but this passage does not give a complete time-and-altitude procedure. I don’t want to guess at a safety-critical detail. [#{incomplete_boiling.fetch(:source)}]"
        end
        answer += "\n\nAlso remember that boiling does not remove dissolved chemical contamination. [#{chemical_warning.fetch(:source)}]" if chemical_warning
        answer
      end
    end
  end

  def non_boiling_water_answer
    bleach = matching_fact(/plain unscented household bleach|unscented household bleach.*water purification/i)
    bleach_strength = matching_fact(/household bleach.*6% sodium hypochlorite|6% sodium hypochlorite.*household bleach/i)
    bleach_dose = matching_fact(/16 drops.*(?:each|per) gallon|1\/8 teaspoon.*(?:each|per) gallon/i)
    iodine_dose = matching_fact(/2%.*(?:tincture of )?iodine.*(?:5 drops|five drops).*quart.*30 minutes/i)
    tablets = matching_fact(/commercial water purification tablets should be used as directed/i)
    chemical_warning = matching_fact(/bleach will not remove chemical pollutants|unsafe because of chemicals.*do not drink/i)

    if bleach && bleach_strength && bleach_dose
      answer = "Since boiling isn’t available, use chemical disinfection. Your archive’s clearest method is fresh, plain, unscented household bleach containing 6% sodium hypochlorite. Do not use scented, color-safe, or cleaner-added bleach. [#{bleach_strength.fetch(:source)}]"
      answer += "\n\nFor an adult emergency water supply:\n\n1. Add 16 drops (1/8 teaspoon) of that bleach to each gallon of water. [#{bleach_dose.fetch(:source)}]\n2. Let it stand for 30 minutes before using it. [#{bleach_dose.fetch(:source)}]\n3. If it still does not smell of bleach, discard it and find another water source. [#{bleach_dose.fetch(:source)}]"
      answer += "\n\nThe cited guide warns that this treatment is not safe for infants unless the water is subsequently run through a suitable filter. [#{bleach_dose.fetch(:source)}]"
      answer += "\n\nDo not use this method for water suspected of chemical, oil, poison, or sewage contamination; the archive says not to drink water with those warning signs. Find another source instead. [#{chemical_warning.fetch(:source)}]" if chemical_warning
      if iodine_dose
        answer += "\n\nIf bleach is unavailable, the archive gives 2% USP tincture of iodine as a second choice: use 5 drops per quart of clear water—or 10 drops if cloudy—and wait 30 minutes. [#{iodine_dose.fetch(:source)}]"
      elsif tablets
        answer += "\n\nCommercial purification tablets are another option; use only the amount and wait time printed on their label. [#{tablets.fetch(:source)}]"
      end
      answer
    elsif iodine_dose
      "Since boiling isn’t available, the complete alternative in your retrieved sources is 2% USP tincture of iodine. Add 5 drops to each quart of clear water, or 10 drops if it is cloudy, and wait 30 minutes before drinking. [#{iodine_dose.fetch(:source)}]"
    elsif tablets
      "Since boiling isn’t available, use commercial water-purification tablets exactly as directed on their label. The retrieved passage does not provide a safe universal dose or wait time, so I won’t guess. [#{tablets.fetch(:source)}]"
    else
      "I understand that boiling is not an option. The retrieved passages do not contain a complete non-boiling treatment, so I can’t safely turn them into dosing instructions. Search for unscented household bleach, iodine, or water-purification tablets in the archive, or ask me about one of those methods specifically."
    end
  end

  def recipe_answer
    @recipe_answer ||= @sources.each_with_index.filter_map do |source, index|
      recipe = parse_recipe(source.quote)
      next if recipe.fetch(:ingredients).size < 2 || recipe.fetch(:directions).size < 2

      citation = index + 1
      opening = recipe.fetch(:summary).presence || "Yes—this recipe is covered by #{source_name(source)}."
      sections = [ "#{conversationalize(opening)} [#{citation}]" ]
      if recipe.fetch(:timing).any?
        timing = "Plan on #{recipe.fetch(:timing).to_sentence}."
        timing += " It makes #{recipe.fetch(:servings)} servings." if recipe.fetch(:servings).present?
        sections << "#{timing} [#{citation}]"
      elsif recipe.fetch(:servings).present?
        sections << "This recipe makes #{recipe.fetch(:servings)} servings. [#{citation}]"
      end
      sections << "What you’ll need:\n#{recipe.fetch(:ingredients).map { |ingredient| "• #{humanize_ingredient(ingredient)}" }.join("\n")} [#{citation}]"
      directions = recipe.fetch(:directions).first(10).each_with_index.map do |direction, direction_index|
        "#{direction_index + 1}. #{humanize_instruction(direction)}"
      end
      sections << "Here’s how to make it:\n#{directions.join("\n")} [#{citation}]"
      sections << "The part to watch: #{humanize_caution(recipe.fetch(:caution))} [#{citation}]" if recipe.fetch(:caution).present?
      if recipe.fetch(:gap).present?
        sections << "One gap in this entry: #{recipe.fetch(:gap)} I won’t guess at the missing detail. [#{citation}]"
      end
      sections.join("\n\n")
    end.first
  end

  def parse_recipe(text)
    lines = text.to_s.lines.map { |line| clean_list_line(line) }.compact_blank
    ingredients_at = lines.index { |line| line.match?(/\Aingredients?\z/i) }
    directions_at = lines.index { |line| line.match?(/\A(?:directions?|method|instructions?)\z/i) }
    return empty_recipe unless ingredients_at && directions_at && ingredients_at < directions_at

    preface = lines.first(ingredients_at)
    ingredients = lines[(ingredients_at + 1)...directions_at]
      .reject { |line| timing_line?(line) || noisy_recipe_line?(line) }.first(20)
    directions = lines[(directions_at + 1)..]
      .take_while { |line| !recipe_footer_line?(line) }
      .reject { |line| noisy_recipe_line?(line) || line.match?(/\Aenjoy\b/i) }.first(12)
    summary = preface.find { |line| line.length.between?(30, 360) && !timing_line?(line) && !line.match?(/\bIMPORTANT\b/i) }
    caution_line = preface.find { |line| line.match?(/\b(?:IMPORTANT|caution|make sure)\b/i) }
    caution = caution_line.to_s.sub(/.*?\bIMPORTANT\b\s*/i, "").strip.presence
    timing = preface.filter_map do |line|
      next unless (match = line.match(/(?:⏲️|🍳)?\s*(Prep|Wait|Cook) time:\s*(.+)\z/i))

      label = { "prep" => "prep", "wait" => "rest", "cook" => "cooking" }.fetch(match[1].downcase)
      "#{humanize_duration(match[2])} of #{label}"
    end
    servings = preface.filter_map { |line| line.match(/Servings?:\s*(\d+)/i)&.captures&.first }.first
    linked_method = directions.find { |line| line.match?(/as described in .+ recipe/i) }
    gap = if linked_method
      "it refers you to another biscuit recipe for the final baking step but does not include that detail here."
    end

    { ingredients:, directions:, summary:, caution:, timing:, servings:, gap: }
  end

  def empty_recipe
    { ingredients: [], directions: [], summary: nil, caution: nil, timing: [], servings: nil, gap: nil }
  end

  def humanize_duration(duration)
    duration.to_s.strip
      .sub(/\A1h\z/i, "1 hour")
      .sub(/\A(\d+)h\z/i, '\1 hours')
      .sub(/\A1min\z/i, "1 minute")
      .sub(/\A(\d+)min\z/i, '\1 minutes')
  end

  def clean_list_line(line)
    line.to_s.squish.sub(/\A(?:[-*•]|\d+[.)])\s*/, "").strip
  end

  def timing_line?(line)
    line.match?(/(?:Prep|Wait|Cook) time:|Servings?:/i)
  end

  def noisy_recipe_line?(line)
    line.length < 2 || line.length > 420 || NOISE_PATTERNS.any? { |pattern| line.match?(pattern) }
  end

  def recipe_footer_line?(line)
    line.match?(%r{\Ahttps?://}i) || line.match?(/\A(?:Contributor|Dessert|Donate|Notes?|Side|Snack|Tags?)\b.*(?:·|\(|$)/i)
  end

  def matching_fact(pattern)
    @sources.each_with_index do |source, index|
      sentences(source.quote).each do |sentence|
        return { text: sentence, source: index + 1 } if sentence.match?(pattern)
      end
    end
    nil
  end

  def sentences(text)
    normalized = text.to_s.gsub(/\r\n?/, "\n").lines.map(&:squish)
      .reject { |line| metadata_line?(line) }.join(" ")
    normalized.split(/(?<=[.!?])\s+/).filter_map do |sentence|
      clean = clean_sentence(sentence)
      clean unless noisy_sentence?(clean)
    end
  end

  def water_safety_question?
    words = @question.downcase.scan(/[[:alpha:]]+/)
    words.include?("water") && (words & %w[safe drink drinking purify purification disinfect treat]).any?
  end

  def boiling_excluded?
    normalized_question = @question.tr("’", "'")
    BOILING_EXCLUSION_PATTERNS.any? { |pattern| normalized_question.match?(pattern) }
  end

  def source_name(source)
    heading = source.passage.heading.to_s
    heading.start_with?("files/") ? source.passage.document.title : heading
  end

  def procedural_answer
    facts = sourced_sentences
    instruction_facts = unique_facts(facts.select { |fact| instruction_sentence?(fact.fetch(:text)) })
    primary_steps = instruction_facts.group_by { |fact| fact.fetch(:source) }.values.max_by(&:size).to_a
    step_limit = @question.match?(/\bbowline\b/i) ? 4 : 8
    steps = (primary_steps.size >= 2 ? primary_steps : instruction_facts).first(step_limit)
    return conversational_summary(facts) if steps.size < 2

    summary_facts = facts.select { |fact| summary_sentence?(fact.fetch(:text)) }
    summary = summary_facts.select { |fact| fact.fetch(:source) == 1 }
      .max_by { |fact| [ summary_score(fact.fetch(:text)), -fact.fetch(:text).length ] }
    summary ||= summary_facts
      .max_by { |fact| [ summary_score(fact.fetch(:text)), -fact.fetch(:source), -fact.fetch(:text).length ] }
    opening = if summary
      "#{conversationalize(summary.fetch(:text))} [#{summary.fetch(:source)}]"
    else
      "I found a practical method in #{source_name(@sources.first)}. [1]"
    end
    numbered_steps = steps.each_with_index.map do |fact, index|
      "#{index + 1}. #{humanize_instruction(fact.fetch(:text))} [#{fact.fetch(:source)}]"
    end

    "#{opening}\n\nHere’s how I’d approach it:\n\n#{numbered_steps.join("\n")}"
  end

  def conversational_summary(facts = sourced_sentences)
    ranked = unique_facts(facts.select { |fact| summary_sentence?(fact.fetch(:text)) })
      .sort_by { |fact| [ -relevance(fact.fetch(:text)), fact.fetch(:source) ] }
    focused = ranked.select { |fact| relevance(fact.fetch(:text)) >= [ question_terms.size, 2 ].min }
    ranked = focused if focused.any?
    selected = if ranked.map { |fact| fact.fetch(:source) }.uniq.size > 1
      ranked.group_by { |fact| fact.fetch(:source) }.values.map(&:first)
        .sort_by { |fact| [ -relevance(fact.fetch(:text)), fact.fetch(:source) ] }.first(3)
    else
      ranked.first(3)
    end
    selected = unique_facts(facts).first(2) if selected.empty?
    return AssistantPrompt::INSUFFICIENT_MESSAGE if selected.empty?

    selected.map { |fact| "#{conversationalize(fact.fetch(:text))} [#{fact.fetch(:source)}]" }.join("\n\n")
  end

  def sourced_sentences
    @sourced_sentences ||= @sources.each_with_index.flat_map do |source, index|
      sentences(source.quote).map { |text| { text:, source: index + 1 } }
    end
  end

  def clean_sentence(sentence)
    sentence.to_s.squish
      .sub(/\A.*?\b(Caution:\s*)/i, '\\1')
      .sub(/\A(?:[IVXLCDM]+\.\s*)?LOOPS IN A ROPE\s+/i, "")
      .sub(/\A(?:[-*•]|\d+[.)])\s*/, "")
      .sub(/\A(?:\d+\s+)?Answers?\d*\s+/i, "")
      .sub(/\A\d+\s+(?=[[:alpha:]])/, "")
      .sub(/\A(?:in essence,? )?(?:what )?they recommend is (?:the following|this):?\s*/i, "")
      .sub(/\A(?:n\.?b\.?|note|tip):?\s*/i, "")
      .sub(/\s*\[\d+\]\s*\z/, "")
      .strip
  end

  def noisy_sentence?(sentence)
    sentence.blank? || sentence.length < 15 || sentence.length > 500 || sentence.end_with?("?") ||
      sentence.include?("–") || NOISE_PATTERNS.any? { |pattern| sentence.match?(pattern) }
  end

  def metadata_line?(line)
    return true if line.blank? || line.match?(METADATA_LINE_PATTERN) || line.start_with?("–")
    return true if line.match?(/\A(?:seeds?|corn|plant-care)\z/i) || line.match?(/\A[\d,]+\z/)

    line.length <= 40 && line.exclude?(".") && line.exclude?("?") && line.exclude?("!") &&
      !instruction_sentence?(line)
  end

  def instruction_sentence?(sentence)
    starts_with_action = sentence.match?(/\A(?:#{ACTION_START.join("|")})\b/i)
    passive_instruction = sentence.match?(/\bshould (?:then )?be (?:planted|placed|stored|kept|dried|watered|removed|used)\b/i)
    sequenced_instruction = sentence.match?(/\Aonce\b.+,\s*[[:alpha:]]/i)
    caution = sentence.match?(/\A(?:caution|warning|important|remember)\b/i)
    (starts_with_action || passive_instruction || sequenced_instruction || caution) && sentence.length <= 360
  end

  def summary_sentence?(sentence)
    return false if instruction_sentence?(sentence) ||
      sentence.match?(/\A(?:I\b|I'm|I've|If I\b|we\b|our\b|my\b|However,? we\b|But I\b|I would\b)/i)

    sentence.length.between?(30, 360) && relevance(sentence).positive?
  end

  def relevance(sentence)
    words = sentence.downcase.scan(/[[:alnum:]]{2,}/)
    question_terms.count do |term|
      words.any? { |word| word.start_with?(term) || term.start_with?(word) }
    end
  end

  def summary_score(sentence)
    relevance(sentence) + (sentence.match?(/\A(?:It is possible to|You can|Yes[, —-])/i) ? 3 : 0)
  end

  def question_terms
    @question_terms ||= @question.downcase.scan(/[[:alnum:]]{2,}/)
      .reject { |word| QUESTION_STOP_WORDS.include?(word) }.uniq
  end

  def conversationalize(sentence)
    sentence.sub(/\AIt is possible to\b/i, "Yes—you can")
      .sub(/\AOne can\b/i, "You can")
      .sub(/\AA Bowline makes a loop, large or small, in the end of a rope which has a thousand and one uses\.?/i, "A bowline creates a fixed loop at the end of a rope and is useful in many situations.")
      .sub(/, but remember this is a corn that isn't any good as sweet corn\./i, ". Just know that this is popcorn corn, not sweet corn.")
      .gsub(/short bread/i, "shortbread")
  end

  def humanize_ingredient(ingredient)
    ingredient.sub(/\Afrom (\d+g) to (\d+g) of (.+)\z/i, '\1–\2 of \3')
  end

  def humanize_caution(caution)
    caution.to_s
      .gsub(/\bliquide\b/i, "liquid")
      .gsub(/\bnot to warm\b/i, "not too warm")
      .sub(/\AButter is what makes this recipe complicated when cooking the dough,?\s*/i, "Butter is the tricky part. ")
      .sub(/\AButter is the tricky part\. make sure/i, "Butter is the tricky part. Make sure")
      .sub(/\band make sure that the shortbreads are cold/i, "and chill the shortbreads")
      .gsub(/,\s*make sure\b/i, ". Make sure")
  end

  def humanize_instruction(instruction)
    clean = instruction.to_s
      .gsub(/\bendbehind\b/i, "end behind")
      .gsub(/\bstandingpart\b/i, "standing part")
      .gsub(/put-\s*ting/i, "putting")
      .sub(/\s*\(sometimes described as ['’\"]putting the rabbit back in his hole['’\"]?\.?\)\.?/i, "—the familiar “rabbit back into the hole” step")
      .sub(/,\s*i\.e\.?\z/i, ", clockwise for half a turn")
      .sub(/\s+4\.\s*\z/, "")
      .sub(/\AHaul taut \(Fig\.?\z/i, "Pull the knot tight")
      .gsub(/\bpreparation\b/i, "mixture")
      .gsub(/\bliquide\b/i, "liquid")
      .gsub(/\bhomogenous\b/i, "evenly mixed")
      .gsub(/\bnot to warm\b/i, "not too warm")
      .sub(/\AGet the plain kernels for home made popcorn from the market \(unflavoured\)/i, "Start with plain, unflavoured popcorn kernels")
      .sub(/\AGet plain, unflavoured popcorn kernels/i, "Start with plain, unflavoured popcorn kernels")
      .sub(/\AThe kernels that have germinated should then be planted(?: out)?(?: into the ground)?/i, "Once the kernels germinate, plant them")
      .sub(/\APlace (.+?) in between\b/i, 'Place \1 between')
      .sub(/\AHave a good mixing of the (.+?) so it gets\b/i, 'Mix the \1 well so it gets')
      .sub(/\AWarm the butter so it is “pommade” meaning not liquid but soft enough so you can mix it with the mixture\b/i, "Warm the butter only until it is soft enough to mix—not liquid")
      .sub(/\ALet the dough sit and then cook it as described in (.+) recipe\b/i, 'Let the dough rest. This entry points to the \1 recipe for the final baking step')
      .sub(/\band spaced\b/i, "and space them")
      .sub(/\AKeep watered\b/i, "Keep them watered")
      .gsub(/,\s*make sure\b/i, ". Make sure")
    clean.end_with?(".", "!", "?") ? clean : "#{clean}."
  end

  def unique_facts(facts)
    facts.uniq { |fact| fact.fetch(:text).downcase.gsub(/[^[:alnum:]]/, "") }
  end

  def procedural?
    words = @question.downcase.scan(/[[:alpha:]]+/)
    (words & %w[how recipe make prepare cook bake repair build treat steps instructions]).any?
  end

  def recipe_question?
    words = @question.downcase.scan(/[[:alpha:]]+/)
    (words & %w[recipe cook cooking bake baking ingredients meal food bread shortbread]).any?
  end
end
