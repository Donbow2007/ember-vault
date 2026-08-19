class SourceAnswerFormatter
  def initialize(question:, sources:)
    @question = question.to_s
    @sources = sources
  end

  def call
    return AssistantPrompt::INSUFFICIENT_MESSAGE if @sources.empty?
    return water_safety_answer if water_safety_question? && water_safety_answer.present?

    if procedural?
      "Here’s the practical guidance supported by #{source_name(@sources.first)}:\n\n#{@sources.first.quote.to_s.strip} [1]"
    else
      @sources.each_with_index.map do |source, index|
        "#{source.quote.to_s.strip} [#{index + 1}]"
      end.join("\n\n")
    end
  end

  private

  def water_safety_answer
    @water_safety_answer ||= begin
      filter = matching_fact(/cloudy water should be filtered/i)
      boil = matching_fact(/rolling boil.*(?:one|1).*minute|boil clear water.*(?:one|1).*minute/i)
      cool = matching_fact(/(?:let|allow) the water cool before drinking/i)
      storage = matching_fact(/store treated water in a clean covered container/i)
      chemical_warning = matching_fact(/chemical pollutants?.*(?:not|won't|will not).*remov|(?:not|won't|will not).*remove.*chemical pollutants?/i)

      if boil.present?
        steps = [ filter, boil, cool, storage ].compact.each_with_index.map do |fact, index|
          "#{index + 1}. #{fact.fetch(:text)} [#{fact.fetch(:source)}]"
        end
        answer = "Use boiling when you can. It is the clearest supported emergency treatment in your local library. [#{boil.fetch(:source)}]\n\nSTEPS\n\n#{steps.join("\n")}"
        if chemical_warning
          answer += "\n\nIMPORTANT LIMIT\n\n#{chemical_warning.fetch(:text)} [#{chemical_warning.fetch(:source)}]"
        end
        answer
      end
    end
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
    text.to_s.split(/(?<=[.!?])\s+|\n+/).map(&:squish)
      .reject { |sentence| sentence.blank? || sentence.match?(/\Ahttps?:|Page \d+ of \d+/i) }
  end

  def water_safety_question?
    words = @question.downcase.scan(/[[:alpha:]]+/)
    words.include?("water") && (words & %w[safe drink drinking purify purification disinfect treat]).any?
  end

  def source_name(source)
    heading = source.passage.heading.to_s
    heading.start_with?("files/") ? source.passage.document.title : heading
  end

  def procedural?
    words = @question.downcase.scan(/[[:alpha:]]+/)
    (words & %w[how recipe make prepare cook bake repair build treat steps instructions]).any?
  end
end
