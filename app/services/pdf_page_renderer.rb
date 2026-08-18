require "open3"
require "tempfile"
require "tmpdir"
require "timeout"

class PdfPageRenderer
  BINARY = "/usr/bin/pdftoppm"
  MAX_PDF_SIZE = 50.megabytes

  def initialize(document, passage)
    @document = document
    @passage = passage
  end

  def call
    raise "PDF page renderer is unavailable" unless File.executable?(BINARY)

    content = pdf_content
    raise "PDF source is too large to render" if content.bytesize > MAX_PDF_SIZE

    Tempfile.create([ "ember-vault-source", ".pdf" ], binmode: true) do |pdf|
      pdf.write(content)
      pdf.flush
      Dir.mktmpdir("ember-vault-page") do |directory|
        output_root = File.join(directory, "page")
        _output, error, status = Timeout.timeout(45) do
          Open3.capture3(BINARY, "-f", @passage.source_page.to_s, "-l", @passage.source_page.to_s,
            "-singlefile", "-png", "-scale-to", "2200", pdf.path, output_root)
        end
        raise "PDF page rendering failed: #{error.to_s.first(200)}" unless status.success?

        File.binread("#{output_root}.png")
      end
    end
  end

  private

  def pdf_content
    if @document.content_type == "application/x-openzim"
      raise "Original PDF source is unavailable" unless @passage.source_entry_index

      ZimReader.new(Rails.root.join(@document.stored_path)).content_by_index(@passage.source_entry_index)
    elsif File.extname(@document.original_filename).downcase == ".pdf"
      File.binread(Rails.root.join(@document.stored_path))
    else
      raise "Original PDF source is unavailable"
    end
  end
end
