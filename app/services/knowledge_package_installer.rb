require "zip"
require "digest"
require "fileutils"
require "securerandom"

class KnowledgePackageInstaller
  MAX_EXTRACTED_BYTES = 512.megabytes
  MAX_ENTRY_BYTES = 64.megabytes
  MAX_ENTRIES = 5_000
  REQUIRED_METADATA = %w[id slug title category version content_hash].freeze

  def initialize(download) = @download = download

  def call
    archive = EmberVault::Paths.resolve(@download.destination_path)
    verify_archive!(archive)
    @download.update!(status: "installing", error_message: nil)
    destination = install_destination
    staging = destination.dirname.join(".#{destination.basename}.staging-#{SecureRandom.hex(8)}")
    backup = destination.dirname.join(".#{destination.basename}.backup-#{SecureRandom.hex(8)}")
    FileUtils.mkdir_p(staging)
    begin
      extract_safely!(archive, staging)
      load_articles!(staging)
      File.rename(destination, backup) if destination.exist?
      File.rename(staging, destination)
      @download.update!(status: "indexing")
      KnowledgePackIndexJob.perform_later(@download, backup.to_s)
    rescue StandardError
      FileUtils.rm_rf(destination) if backup.exist? && destination.exist?
      File.rename(backup, destination) if backup.exist?
      raise
    ensure
      FileUtils.rm_rf(staging) if staging.exist?
    end
  end

  def finalize(backup_path:)
    destination = install_destination
    backup = Pathname(backup_path)
    articles = load_articles!(destination)
    ContentDownload.transaction do
      persist_documents!(articles, destination)
      @download.documents.order(:id).find_each do |document|
        DocumentIndexer.new(document, rebuild_search_index: false).call
        raise document.error_message if document.reload.status == "failed"
      end
      Passage.rebuild_search_index
      @download.update!(status: "installed", installed_package_version: @download.package_version,
        installed_content_hash: @download.content_hash, error_message: nil)
    end
    FileUtils.rm_rf(backup) if backup.exist?
  rescue StandardError
    FileUtils.rm_rf(destination) if destination.exist?
    File.rename(backup, destination) if backup.exist?
    raise
  end

  private

  def verify_archive!(archive)
    raise "Knowledge package archive is missing" unless archive.file?
    raise "Knowledge package exceeds the maximum allowed size" if archive.size > ContentFetcher::MAX_KNOWLEDGE_PACKAGE_BYTES
    expected = @download.content_hash.to_s.downcase
    raise "Knowledge package checksum is missing" unless expected.match?(/\A[0-9a-f]{64}\z/)
    actual = Digest::SHA256.file(archive).hexdigest
    raise "Knowledge package hash verification failed" unless ActiveSupport::SecurityUtils.secure_compare(expected, actual)
  end

  def extract_safely!(archive, staging)
    count = 0
    extracted_bytes = 0
    Zip::File.open(archive) do |zip|
      zip.each do |entry|
        count += 1
        raise "Knowledge package contains too many files" if count > MAX_ENTRIES
        validate_entry!(entry, staging)
        next if entry.directory?
        raise "Knowledge package entry is too large" if entry.size > MAX_ENTRY_BYTES
        extracted_bytes += entry.size
        raise "Knowledge package expands beyond the allowed size" if extracted_bytes > MAX_EXTRACTED_BYTES
        target = staging.join(entry.name).cleanpath
        FileUtils.mkdir_p(target.dirname)
        entry.extract(target) { raise "Duplicate path in knowledge package" }
      end
    end
  rescue Zip::Error => error
    raise "Malformed knowledge package: #{error.message}"
  end

  def validate_entry!(entry, staging)
    name = entry.name.to_s.tr("\\", "/")
    raise "Unsafe path in knowledge package" if name.blank? || name.start_with?("/", "\\") || name.match?(/\A[A-Za-z]:/)
    raise "Unsafe path in knowledge package" unless EmberVault::Paths.within?(staging.join(name).cleanpath, staging)
    raise "Symbolic links are not allowed in knowledge packages" if (entry.unix_perms.to_i & 0o170000) == 0o120000
  end

  def load_articles!(staging)
    article_paths = staging.glob("*/article.md").sort
    raise "Knowledge package contains no articles" if article_paths.empty?
    raise "Articles must be stored in top-level article directories" if (staging.glob("**/article.md") - article_paths).any?
    ids = Set.new
    article_paths.map do |article_path|
      metadata_path = article_path.dirname.join("metadata.json")
      raise "Article metadata is missing" unless metadata_path.file?
      metadata = JSON.parse(metadata_path.read)
      validate_metadata!(metadata)
      raise "Duplicate article ID in knowledge package" unless ids.add?(metadata.fetch("id"))
      { relative_path: article_path.relative_path_from(staging), metadata: }
    rescue JSON::ParserError
      raise "Article metadata is invalid JSON"
    end
  end

  def validate_metadata!(metadata)
    raise "Article metadata must be an object" unless metadata.is_a?(Hash)
    raise "Article metadata is incomplete" unless REQUIRED_METADATA.all? { |key| metadata[key].present? }
    raise "Article version is invalid" unless metadata["version"].is_a?(Integer) && metadata["version"].positive?
    raise "Article images must be an array" if metadata.key?("images") && !metadata["images"].is_a?(Array)
    Array(metadata["images"]).each do |image|
      raise "Article image path is invalid" unless image.is_a?(String) && image.start_with?("images/") && !image.split("/").include?("..")
    end
  end

  def persist_documents!(articles, destination)
    retained_ids = []
    articles.each do |article|
        metadata = article.fetch(:metadata)
        path = destination.join(article.fetch(:relative_path))
        document = @download.documents.find_or_initialize_by(external_id: metadata.fetch("id"))
        document.assign_attributes(title: metadata.fetch("title"), original_filename: article.fetch(:relative_path).to_s,
          content_type: "text/markdown", stored_path: EmberVault::Paths.relative(path), byte_size: path.size,
          content_hash: metadata.fetch("content_hash"), status: "queued", error_message: nil)
        document.save!
        retained_ids << document.id
    end
    stale = @download.documents.where.not(id: retained_ids)
    Passage.where(document_id: stale.select(:id)).delete_all
    stale.delete_all
  end

  def install_destination
    safe_id = @download.package_id.to_s.gsub(/[^a-zA-Z0-9_.-]/, "-")
    raise "Knowledge package ID is missing" if safe_id.blank?
    EmberVault::Paths.content_for("knowledge-pack").join(safe_id)
  end
end
