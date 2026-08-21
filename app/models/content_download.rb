require "uri"

class ContentDownload < ApplicationRecord
  STATUSES = %w[queued downloading cancel_requested cancelled delete_requested deleting deletion_failed complete failed].freeze
  scope :failed, -> { where(status: "failed") }
  has_many :documents, dependent: :destroy
  has_many :map_features, dependent: :destroy

  validates :resource_id, :title, :source_url, :kind, presence: true
  validates :resource_id, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  def progress
    return 100 if status == "complete"
    return 0 if expected_bytes.to_i.zero?

    [ (downloaded_bytes.to_f / expected_bytes.to_i * 100).round, 100 ].min
  end

  def display_total_bytes
    status == "complete" ? downloaded_bytes : expected_bytes
  end

  def active?
    status.in?(%w[queued downloading cancel_requested delete_requested deleting])
  end

  def deletion_progress
    return 0 if deletion_total.to_i.zero?

    (deletion_remaining.to_f / deletion_total * 100).ceil.clamp(0, 100)
  end

  def file_available?
    return false unless status == "complete" && destination_path.present?

    EmberVault::Paths.resolve(destination_path).file?
  rescue ArgumentError
    false
  end

  def enqueue_deletion!
    total = Passage.where(document_id: documents.select(:id)).count
    update!(status: "deleting", deletion_total: total, deletion_remaining: total, error_message: nil)
    DeleteContentDownloadJob.perform_later(self)
  end

  def enqueue_indexing!
    return KnowledgePackageInstaller.new(self).call if kind == "knowledge-pack"
    return unless kind.in?(%w[zim document]) && status == "complete" && destination_path.present?

    document = documents.first_or_initialize
    document.assign_attributes(title:, original_filename: File.basename(destination_path), content_type: document_content_type,
      stored_path: destination_path, byte_size: downloaded_bytes.to_i, status: "queued", error_message: nil)
    document.save!
    kind == "zim" ? ZimIndexJob.perform_later(document) : IndexDocumentJob.perform_later(document)
  end

  def enqueue_map_indexing!
    MapIndexJob.perform_later(self) if kind == "map" && status == "complete" && destination_path.present?
  end

  def remove_content_files
    paths = [ inferred_destination_path ]
    if destination_path.present?
      begin
        paths << EmberVault::Paths.resolve(destination_path)
      rescue ArgumentError
        nil
      end
    end
    paths.flat_map { |path| [ path, path.sub_ext("#{path.extname}.part") ] }.uniq.each do |path|
      next unless [ EmberVault::Paths.content, EmberVault::Paths.models ].any? { |root| EmberVault::Paths.within?(path, root) }

      File.delete(path) if File.file?(path)
    end
  end

  def inferred_destination_path
    extension = download_extension
    safe_id = resource_id.gsub(/[^a-zA-Z0-9_.-]/, "-")
    root = kind == "model" ? EmberVault::Paths.models : EmberVault::Paths.content_for(kind)
    root.join("#{safe_id}#{extension}")
  end

  def download_extension
    source_extension = File.extname(URI(source_url).path).presence
    return source_extension if source_extension

    if kind == "map"
      ".pmtiles"
    elsif kind == "model"
      ".gguf"
    elsif kind == "document"
      resource_id.start_with?("pmc-") ? ".json" : ".txt"
    elsif kind == "knowledge-pack"
      ".zip"
    else
      ".zim"
    end
  end

  def document_content_type
    return "application/x-openzim" if kind == "zim"

    { ".pdf" => "application/pdf", ".json" => "application/json", ".html" => "text/html", ".htm" => "text/html" }
      .fetch(File.extname(destination_path).downcase, "text/plain")
  end
end
