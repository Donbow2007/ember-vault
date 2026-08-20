require "pdf-reader"

class DocumentIndexer
  MAX_PASSAGE_LENGTH = 1_600

  def initialize(document)
    @document = document
  end

  def call
    @document.update!(status: "indexing", error_message: nil)
    sections = extract_sections
    passage_attributes = []
    sections.each do |text, page|
      chunk(text).each do |body|
        passage_attributes << { body:, page: }
      end
    end
    raise "No readable text was found in this document" if passage_attributes.empty?

    Document.transaction do
      @document.passages.delete_all
      passage_attributes.each_with_index do |attributes, position|
        @document.passages.create!(position:, heading: heading_for(attributes[:body]), body: attributes[:body],
          source_path: pdf? ? @document.original_filename : nil, source_mime: pdf? ? "application/pdf" : nil,
          source_page: attributes[:page])
      end
      @document.update!(status: "ready", passage_count: passage_attributes.length)
    end
    Passage.rebuild_search_index
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
