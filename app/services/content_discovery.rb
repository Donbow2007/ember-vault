require "net/http"
require "json"

class ContentDiscovery
  Result = Data.define(:resource_id, :title, :creator, :description, :source, :source_url, :kind, :size_bytes, :license) do
    def token
      Rails.application.message_verifier(:content_discovery).generate(to_h, expires_in: 2.hours)
    end
  end

  def local(query)
    terms = search_terms(query)
    return [] if terms.empty?

    ContentCatalog.new.searchable_resources.filter_map do |resource|
      haystack = [ resource["title"], resource["name"], resource["description"], resource["id"] ].join(" ").downcase
      next unless terms.all? { |term| haystack.include?(term) }

      result_from(resource.merge("source" => "Kiwix catalog", "license" => "Source license"))
    end.first(30)
  end

  def remote(query)
    terms = search_terms(query)
    return [] if terms.empty?

    open_library_books(query)
  rescue StandardError => error
    Rails.logger.warn("Content discovery failed: #{error.class}: #{error.message}")
    []
  end

  def self.verify(token)
    attributes = Rails.application.message_verifier(:content_discovery).verify(token).symbolize_keys
    Result.new(**attributes.slice(*Result.members))
  end

  private

  def open_library_books(query)
    uri = URI("https://openlibrary.org/search.json")
    uri.query = URI.encode_www_form(q: "#{query} ebook_access:public language:eng",
      fields: "key,title,author_name,first_publish_year,ia,public_scan_b,ebook_access", limit: 20)
    documents = get_json(uri).fetch("docs", [])
    books = documents.select { |item| item["public_scan_b"] && item["ebook_access"] == "public" && item["ia"].present? }
      .reject { |item| item["title"].to_s.match?(/\b(thesis|dissertation|proceedings|journal)\b/i) }
      .first(10)
    parallel_map(books, concurrency: 4) do |item|
        identifier, file = archive_book_file(Array(item["ia"]))
        next unless file

        Result.new(resource_id: "openlibrary-#{item.fetch('key').delete_prefix('/works/')}-#{Digest::SHA256.hexdigest(file.fetch('name')).first(8)}",
          title: item["title"].to_s.first(300), creator: Array(item["author_name"]).join(", ").first(200),
          description: [ "Public full-text book", item["first_publish_year"] ].compact.join(" · "),
          source: "Open Library / Internet Archive", source_url: archive_download_url(identifier, file.fetch("name")),
          kind: "document", size_bytes: file["size"].to_i, license: "Public full-text scan")
    end.compact
  end

  def archive_book_file(identifiers)
    identifiers.first(3).each do |identifier|
      file = archive_file(identifier)
      return [ identifier, file ] if file
    end
    nil
  end

  def internet_archive(query)
    uri = URI("https://archive.org/advancedsearch.php")
    uri.query = URI.encode_www_form(q: %(title:(#{query}) AND mediatype:texts AND licenseurl:*),
      fl: "identifier,title,creator,description,licenseurl", rows: 16, output: "json")
    documents = get_json(uri).dig("response", "docs") || []
    documents.select { |item| item["licenseurl"].to_s.match?(/creativecommons|publicdomain/i) }.first(8).filter_map do |item|
      license = item["licenseurl"].to_s
      file = archive_file(item.fetch("identifier"))
      next unless file

      Result.new(resource_id: "archive-#{item.fetch('identifier')}-#{Digest::SHA256.hexdigest(file.fetch('name')).first(10)}",
        title: item["title"].to_s.first(300), creator: Array(item["creator"]).join(", ").first(200),
        description: Array(item["description"]).join(" ").first(500), source: "Internet Archive",
        source_url: archive_download_url(item.fetch("identifier"), file.fetch("name")), kind: "document",
        size_bytes: file["size"].to_i, license: license)
    end
  end

  def archive_file(identifier)
    metadata = get_json(URI("https://archive.org/metadata/#{URI.encode_uri_component(identifier)}"))
    files = metadata.fetch("files", [])
    files.find { |file| file["name"].to_s.end_with?("_djvu.txt") } ||
      files.find { |file| file["name"].to_s.match?(/\.pdf\z/i) && file["source"] != "original" } ||
      files.find { |file| file["name"].to_s.match?(/\.(txt|pdf)\z/i) }
  end

  def archive_download_url(identifier, filename)
    encoded = filename.split("/").map { |part| URI.encode_uri_component(part) }.join("/")
    "https://archive.org/download/#{URI.encode_uri_component(identifier)}/#{encoded}"
  end

  def pubmed_central(query)
    search_uri = URI("https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi")
    scoped_query = search_terms(query).map { |term| "#{term}[Title/Abstract]" }.join(" AND ")
    indexed_years = "1900:#{Date.current.year - 1}[Publication Date]"
    search_uri.query = URI.encode_www_form(db: "pmc", term: "#{scoped_query} AND open access[filter] AND #{indexed_years}", retmode: "json", retmax: 8)
    ids = get_json(search_uri).dig("esearchresult", "idlist") || []
    return [] if ids.empty?

    summary_uri = URI("https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi")
    summary_uri.query = URI.encode_www_form(db: "pmc", id: ids.join(","), retmode: "json")
    summaries = get_json(summary_uri).fetch("result", {})
    ids.filter_map do |id|
      item = summaries[id]
      next unless item

      pmcid = item["articleids"]&.find { |entry| entry["idtype"] == "pmc" }&.fetch("value", nil) || "PMC#{id}"
      Result.new(resource_id: "pmc-#{pmcid.downcase}", title: item["title"].to_s.first(300),
        creator: Array(item["authors"]).filter_map { |author| author["name"] }.join(", ").first(200),
        description: "Open-access biomedical full text prepared for local indexing.", source: "PubMed Central OA",
        source_url: "https://www.ncbi.nlm.nih.gov/research/bionlp/RESTful/pmcoa.cgi/BioC_JSON/#{pmcid}/UNICODE",
        kind: "document", size_bytes: 0, license: "PMC Open Access — verify article license")
    end
  end

  def get_json(uri)
    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "EmberVault/1.0 (offline knowledge downloader)"
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20) { |http| http.request(request) }
    raise "Discovery request failed with HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  def parallel_map(items, concurrency:)
    items.each_slice(concurrency).flat_map do |batch|
      batch.map { |item| Thread.new { yield item } }.map(&:value)
    end
  end

  def result_from(resource)
    Result.new(resource_id: resource.fetch("id"), title: resource["title"] || resource["name"], creator: nil,
      description: resource["description"], source: resource.fetch("source"), source_url: resource.fetch("url"),
      kind: resource.fetch("kind", resource["type"] || "zim"), size_bytes: resource.fetch("size_mb", 0).to_i.megabytes,
      license: resource.fetch("license"))
  end

  def search_terms(query)
    query.to_s.downcase.scan(/[[:alnum:]]{2,}/).first(8)
  end
end
