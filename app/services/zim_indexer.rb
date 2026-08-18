require "stringio"

class ZimIndexer
  MAX_PASSAGE_LENGTH = 1_600

  def initialize(document, reader: nil)
    @document = document
    @reader = reader || ZimReader.new(Rails.root.join(document.stored_path))
  end

  def call
    @document.update!(status: "indexing", error_message: nil)
    passages = build_passages
    raise "No readable text was found in this ZIM archive" if passages.empty?

    Document.transaction do
      @document.passages.delete_all
      passages.each_slice(500) { |batch| @document.passages.insert_all!(batch) }
      @document.update!(status: "ready", passage_count: passages.length)
    end
    Passage.rebuild_search_index
  rescue StandardError => error
    @document.update(status: "failed", error_message: error.message.to_s.first(500))
  end

  private

  def build_passages
    passages = []
    @reader.each_readable_entry do |entry|
      source_sections(entry).each do |text, page|
        chunk(text).each do |body|
          passages << { position: passages.length, heading: clean_heading(entry.title), body:,
            source_entry_index: entry.index, source_path: entry.path, source_mime: entry.mime_type, source_page: page,
            created_at: Time.current, updated_at: Time.current }
        end
      end
    rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError
      next
    end
    passages
  end

  def source_sections(entry)
    content = @reader.content(entry)
    if entry.mime_type == "application/pdf"
      PDF::Reader.new(StringIO.new(content)).pages.each_with_index.map { |page, index| [ page.text, index + 1 ] }
    else
      [ [ ActionView::Base.full_sanitizer.sanitize(content.force_encoding("UTF-8")), nil ] ]
    end
  end

  def chunk(text)
    text.encode("UTF-8", invalid: :replace, undef: :replace, replace: "").gsub(/\r\n?/, "\n")
      .split(/\n{2,}/).map { |part| part.gsub(/[ \t]+/, " ").strip }.reject(&:blank?)
      .flat_map { |paragraph| paragraph.scan(/.{1,#{MAX_PASSAGE_LENGTH}}(?:\s+|\z)/m).map(&:strip) }.reject(&:blank?)
  end

  def clean_heading(title)
    title.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "").strip.first(200).presence || @document.title
  end
end
