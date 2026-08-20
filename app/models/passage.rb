class Passage < ApplicationRecord
  belongs_to :document

  validates :position, presence: true, uniqueness: { scope: :document_id }
  validates :body, presence: true

  def self.search(query, limit: 30, document_ids: nil, match: :all)
    terms = query.to_s.downcase.scan(/[[:alnum:]]{2,}/).first(10)
    return none if terms.empty?
    return none if document_ids&.empty?

    operator = match == :any ? " OR " : " AND "
    match_query = terms.map { |term| "\"#{term.gsub('"', '""')}\"*" }.join(operator)
    conditions = [ "passages_fts MATCH :match_query" ]
    binds = { match_query:, limit: }
    if document_ids
      conditions << "passages.document_id IN (:document_ids)"
      binds[:document_ids] = Array(document_ids).map(&:to_i)
    end
    sql = sanitize_sql_array([ <<~SQL, binds ])
      SELECT passages.*,
             snippet(passages_fts, 1, '<mark>', '</mark>', ' … ', 28) AS excerpt,
             bm25(passages_fts, 4.0, 1.0) AS search_rank
      FROM passages_fts
      JOIN passages ON passages.id = passages_fts.rowid
      WHERE #{conditions.join(" AND ")}
      ORDER BY search_rank
      LIMIT :limit
    SQL
    includes(:document).find_by_sql(sql)
  end

  def self.rebuild_search_index
    connection.execute("INSERT INTO passages_fts(passages_fts) VALUES('rebuild')")
  end

  def self.search_within_documents(query, document_ids:, limit: 30)
    tokens = query.to_s.downcase.scan(/[[:alnum:]]{2,}/).uniq.first(14)
    return none if tokens.empty? || document_ids.empty?

    patterns = tokens.map do |token|
      stem = token.length >= 7 ? token.first(6) : token
      connection.quote("%#{sanitize_sql_like(stem)}%")
    end
    matches = patterns.map { |pattern| "lower(passages.heading) LIKE #{pattern} OR lower(passages.body) LIKE #{pattern}" }
    scores = patterns.map do |pattern|
      "(CASE WHEN lower(passages.heading) LIKE #{pattern} THEN 3 ELSE 0 END + " \
        "CASE WHEN lower(passages.body) LIKE #{pattern} THEN 1 ELSE 0 END)"
    end
    includes(:document).where(document_id: document_ids).where(matches.map { |match_clause| "(#{match_clause})" }.join(" OR "))
      .order(Arel.sql("#{scores.join(' + ')} DESC")).limit(limit)
  end
end
