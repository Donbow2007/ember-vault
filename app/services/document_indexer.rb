require "pdf-reader"

class DocumentIndexer
  MAX_PASSAGE_LENGTH = 1_600

  def initialize(document, rebuild_search_index: true)
    @document = document
    @rebuild_search_index = rebuild_search_index
  end

  def call
    @document.update!(status: "indexing", error_message: nil)
    passage_attributes = markdown? ? markdown_passages : plain_passages
    raise "No readable text was found in this document" if passage_attributes.empty?

    Document.transaction do
      @document.passages.delete_all
      passage_attributes.each_with_index do |attributes, position|
        @document.passages.create!(position:, heading: attributes[:heading].presence || heading_for(attributes[:body]), body: attributes[:body],
          source_path: pdf? ? @document.original_filename : nil, source_mime: pdf? ? "application/pdf" : nil,
          source_page: attributes[:page])
      end
      @document.update!(status: "ready", passage_count: passage_attributes.length)
    end
    Passage.rebuild_search_index if @rebuild_search_index
  rescue StandardError => error
    @document.update(status: "failed", error_message: error.message.to_s.first(500))
  end

  private

  def extract_sections
    path = EmberVault::Paths.resolve(@document.stored_path)
    case File.extname(@document.original_filename).downcase
    when ".pdf"
      PDF::Reader.new(path).pages.each_with_index.map { |page, index| [ page.text, index + 1 ] }
    when ".html", ".htm"
      [ [ ActionView::Base.full_sanitizer.sanitize(File.read(path, encoding: "bom|utf-8")), nil ] ]
    when ".json"
      [ [ json_text(JSON.parse(File.read(path, encoding: "bom|utf-8"))), nil ] ]
    else
      [ [ File.read(path, encoding: "bom|utf-8"), nil ] ]
    end
  end

  def pdf?
    File.extname(@document.original_filename).downcase == ".pdf"
  end

  def markdown?
    @document.content_type == "text/markdown" || File.extname(@document.original_filename).downcase.in?(%w[.md .markdown])
  end

  def plain_passages
    extract_sections.flat_map do |text, page|
      chunk(text).map { |body| { body:, page: } }
    end
  end

  def markdown_passages
    path = EmberVault::Paths.resolve(@document.stored_path)
    article_title = @document.title
    heading = article_title
    sections = []
    buffer = []
    flush = lambda do
      text = buffer.join.strip
      chunk(text).each { |body| sections << { body:, page: nil, heading: [ article_title, heading ].uniq.join(" — ") } } if text.present?
      buffer.clear
    end
    File.foreach(path, encoding: "bom|utf-8") do |line|
      if (match = line.match(/\A\#{1,6}\s+(.+?)\s*\z/))
        flush.call
        heading = match[1].strip
      else
        buffer << line
      end
    end
    flush.call
    sections
  end

  def json_text(value)
    case value
    when Hash then value.values.map { |item| json_text(item) }.join("\n")
    when Array then value.map { |item| json_text(item) }.join("\n")
    when String then value
    else ""
    end
  end

  def chunk(text)
    paragraphs = text.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
      .gsub(/\r\n?/, "\n").split(/\n{2,}/).map { |part| part.gsub(/[ \t]+/, " ").strip }.reject(&:blank?)

    paragraphs.flat_map { |paragraph| paragraph.scan(/.{1,#{MAX_PASSAGE_LENGTH}}(?:\s+|\z)/m).map(&:strip) }.reject(&:blank?)
  end

  def heading_for(body)
    first_line = body.lines.first.to_s.delete_prefix("#").strip
    first_line.length.between?(3, 100) ? first_line : @document.title
  end
end
