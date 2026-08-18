class MapSearch
  ROAD_TYPES = %w[road street avenue highway lane drive boulevard].freeze
  IGNORED_TERMS = %w[ar arkansas].freeze
  ABBREVIATIONS = { "rd" => "road", "st" => "street", "ave" => "avenue", "hwy" => "highway",
    "ln" => "lane", "dr" => "drive", "blvd" => "boulevard" }.freeze

  def initialize(scope)
    @scope = scope
  end

  def call(input, limit: 20)
    query = normalize(input)
    terms = query.split.reject { |term| term.match?(/\A\d+\z/) || term.in?(IGNORED_TERMS) }.first(8)
    return [] if terms.empty?

    lookup_terms = terms - ROAD_TYPES
    patterns = lookup_terms.flat_map do |term|
      escaped = ActiveRecord::Base.sanitize_sql_like(term)
      [ "%#{escaped}%", *(term.length >= 5 ? [ "%#{escaped.first(5)}%" ] : []) ]
    end
    candidates = if patterns.empty?
      @scope.where(category: "roads").limit(5_000).to_a
    else
      clauses = patterns.map { "LOWER(map_features.name) LIKE ?" }.join(" OR ")
      @scope.where(clauses, *patterns).limit(2_000).to_a
    end
    candidates.concat(@scope.where(category: "roads").limit(5_000)) if terms.include?("road")

    candidates.uniq.sort_by { |feature| [ -score(feature, terms, query), feature.name ] }
      .select { |feature| score(feature, terms, query).positive? }.first(limit)
  end

  private

  def normalize(value)
    value.to_s.downcase.gsub(/[^[:alnum:] ]/, " ").split.map { |term| ABBREVIATIONS.fetch(term, term) }.join(" ")
  end

  def score(feature, terms, query)
    name = normalize(feature.name)
    name_terms = name.split
    exact_matches = terms.count { |term| name_terms.include?(term) }
    fuzzy_matches = terms.count do |term|
      term.length >= 5 && !name_terms.include?(term) &&
        name_terms.any? { |name_term| levenshtein_distance(term, name_term) <= (term.length >= 9 ? 2 : 1) }
    end
    value = exact_matches * 4 + fuzzy_matches * 2
    value += 20 if name == query
    value += 8 if query.include?(name) || name.include?(query)
    value += 12 if terms.include?("road") && name_terms.include?("road") && feature.category == "roads" && (exact_matches + fuzzy_matches) >= 2
    road_position = terms.index("road")
    road_name = terms[road_position - 1] if road_position&.positive?
    if road_name && feature.category == "roads" && name_terms.any? { |term| term == road_name || levenshtein_distance(term, road_name) <= 2 }
      value += 16
    end
    value
  end

  def levenshtein_distance(left, right)
    previous = (0..right.length).to_a
    left.each_char.with_index(1) do |left_char, row|
      current = [ row ]
      right.each_char.with_index(1) do |right_char, column|
        current[column] = [ current[column - 1] + 1, previous[column] + 1,
          previous[column - 1] + (left_char == right_char ? 0 : 1) ].min
      end
      previous = current
    end
    previous.last
  end
end
