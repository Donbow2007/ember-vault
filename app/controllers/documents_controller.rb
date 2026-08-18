require "marcel"
require "stringio"

class DocumentsController < ApplicationController
  ALLOWED_EXTENSIONS = %w[.txt .md .markdown .html .htm .csv .json .pdf].freeze
  MAX_FILE_SIZE = 20.megabytes

  def index
    @documents = Document.where(content_download_id: nil).order(created_at: :desc)
    @downloaded_content = ContentDownload.where(status: "complete").includes(:documents).order(created_at: :desc)
    @inventory = (@downloaded_content.map { |download| [ download.created_at, :download, download ] } +
      @documents.map { |document| [ document.created_at, :document, document ] }).sort_by(&:first).reverse
  end

  def show
    @document = Document.find(params[:id])
    @focused_passage = @document.passages.find_by(id: params[:passage_id]) if params[:passage_id].present?
    @focused_passage ||= @document.passages.where.not(source_mime: nil).order(:position).first
    @passages = if @focused_passage
      @document.passages.where(position: (@focused_passage.position - 2)..(@focused_passage.position + 2)).order(:position)
    else
      @document.passages.order(:position).limit(100)
    end
    load_original_source if @focused_passage&.source_mime.present?
  end

  def source_entry
    document = Document.find(params[:id])
    passage = document.passages.find(params[:passage_id])
    return head :not_found unless passage.source_mime == "application/pdf"

    content = original_pdf(document, passage)
    return head :payload_too_large if content.bytesize > 50.megabytes

    send_data content, type: "application/pdf", disposition: "inline", filename: File.basename(passage.source_path)
  end

  def source_page
    document = Document.find(params[:id])
    passage = document.passages.find(params[:passage_id])
    return head :not_found unless passage.source_mime == "application/pdf" && passage.source_page

    image = PdfPageRenderer.new(document, passage).call
    send_data image, type: "image/png", disposition: "inline",
      filename: "#{File.basename(passage.source_path, ".pdf")}-page-#{passage.source_page}.png"
  rescue RuntimeError, Timeout::Error
    head :unprocessable_content
  end

  def zim_asset
    document = Document.find(params[:id])
    path = params[:path].to_s
    return head :not_found unless path.match?(/\.(png|jpe?g|gif|webp|svg|ico)\z/i)

    content = zim_reader(document).content_by_path(path)
    return head :payload_too_large if content.bytesize > 15.megabytes

    send_data content, type: Marcel::MimeType.for(StringIO.new(content), name: path), disposition: "inline"
  rescue RuntimeError
    head :not_found
  end

  def create
    upload = params[:file]
    return redirect_to(documents_path, alert: "Choose a document to import.") unless upload.respond_to?(:original_filename)

    extension = File.extname(upload.original_filename).downcase
    return redirect_to(documents_path, alert: "Unsupported format.") unless ALLOWED_EXTENSIONS.include?(extension)
    return redirect_to(documents_path, alert: "Files must be 20 MB or smaller.") if upload.size > MAX_FILE_SIZE

    archive_dir = Rails.root.join("storage", "archive_files")
    FileUtils.mkdir_p(archive_dir)
    stored_path = archive_dir.join("#{SecureRandom.uuid}#{extension}")
    IO.copy_stream(upload.tempfile, stored_path)
    document = Document.create!(title: params[:title].presence || File.basename(upload.original_filename, extension).humanize,
      original_filename: File.basename(upload.original_filename), content_type: upload.content_type.presence || "application/octet-stream",
      stored_path: stored_path.relative_path_from(Rails.root).to_s, byte_size: upload.size, status: "queued")
    IndexDocumentJob.perform_now(document)
    redirect_to document_path(document), notice: document.ready? ? "Document indexed successfully." : "Document could not be indexed."
  rescue StandardError => error
    File.delete(stored_path) if defined?(stored_path) && File.file?(stored_path)
    redirect_to documents_path, alert: "Import failed: #{error.message.to_s.first(160)}"
  end

  def destroy
    Document.find(params[:id]).destroy!
    redirect_to documents_path, notice: "Document removed from the local archive."
  end

  private

  def load_original_source
    if @focused_passage.source_mime == "text/html"
      html = zim_reader(@document).content_by_index(@focused_passage.source_entry_index)
      @source_html = SourceDocumentRenderer.new(@document, @focused_passage, html).call
    elsif @focused_passage.source_mime == "application/pdf"
      @source_page_url = source_page_document_path(@document, passage_id: @focused_passage.id)
      @source_pdf_url = source_entry_document_path(@document, passage_id: @focused_passage.id,
        anchor: "page=#{@focused_passage.source_page || 1}")
    end
  rescue RuntimeError => error
    @source_error = error.message.to_s.first(200)
  end

  def zim_reader(document)
    raise "Original source is unavailable" unless document.content_type == "application/x-openzim"

    ZimReader.new(Rails.root.join(document.stored_path))
  end

  def original_pdf(document, passage)
    if document.content_type == "application/x-openzim"
      raise "Original PDF source is unavailable" unless passage.source_entry_index

      zim_reader(document).content_by_index(passage.source_entry_index)
    elsif File.extname(document.original_filename).downcase == ".pdf"
      File.binread(Rails.root.join(document.stored_path))
    else
      raise "Original PDF source is unavailable"
    end
  end
end
