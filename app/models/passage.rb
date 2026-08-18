class Passage < ApplicationRecord
  belongs_to :document

  validates :position, presence: true, uniqueness: { scope: :document_id }
  validates :body, presence: true

  def self.search(query, limit: 30)
    terms = query.to_s.downcase.scan(/[[:alnum:]]{2,}/).first(10)
    return none if terms.empty?

    match_query = terms.map { |term| "\"#{term.gsub('"', '""')}\"*" }.join(" AND ")
    sql = sanitize_sql_array([ <<~SQL, { match_query:, limit: } ])
      SELECT passages.*,
             snippet(passages_fts, 1, '<mark>', '</mark>', ' … ', 28) AS excerpt,
             bm25(passages_fts, 4.0, 1.0) AS search_rank
      FROM passages_fts
      JOIN passages ON passages.id = passages_fts.rowid
      WHERE passages_fts MATCH :match_query
      ORDER BY search_rank
      LIMIT :limit
    SQL
    includes(:document).find_by_sql(sql)
  end

  def self.rebuild_search_index
    connection.execute("INSERT INTO passages_fts(passages_fts) VALUES('rebuild')")
  end
end
