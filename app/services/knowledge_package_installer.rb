require "zip"
require "digest"
require "fileutils"

class KnowledgePackageInstaller
  def initialize(download) = @download = download
  def call
    archive = EmberVault::Paths.resolve(@download.destination_path)
    expected = @download.content_hash.to_s.downcase
    actual = Digest::SHA256.file(archive).hexdigest
    raise "Knowledge package hash verification failed" if expected.present? && !ActiveSupport::SecurityUtils.secure_compare(expected, actual)
    destination = EmberVault::Paths.content_for("knowledge-pack").join(@download.package_id.gsub(/[^a-zA-Z0-9_.-]/, "-"))
    FileUtils.mkdir_p(destination); markdown = []
    Zip::File.open(archive) do |zip|
      zip.each do |entry|
        next if entry.directory?
        target = destination.join(entry.name).cleanpath
        raise "Unsafe path in knowledge package" unless EmberVault::Paths.within?(target, destination)
        FileUtils.mkdir_p(target.dirname); entry.extract(target) { true }; markdown << target if target.extname == ".md"
      end
    end
    raise "Knowledge package contains no articles" if markdown.empty?

    retained_ids = markdown.sort.map do |article_path|
      relative_name = article_path.relative_path_from(destination).to_s
      metadata_path = article_path.dirname.join("metadata.json")
      metadata = metadata_path.file? ? JSON.parse(metadata_path.read) : {}
      document = @download.documents.find_or_initialize_by(original_filename: relative_name)
      document.update!(title: metadata["title"].presence || title_from(article_path), content_type: "text/markdown",
        stored_path: EmberVault::Paths.relative(article_path), byte_size: article_path.size, status: "queued", error_message: nil)
      document.id
    end
    @download.documents.where.not(id: retained_ids).destroy_all
    KnowledgePackIndexJob.perform_later(@download)
  end

  private

  def title_from(path)
    heading = path.each_line.lazy.map(&:strip).find { |line| line.start_with?("# ") }
    heading&.delete_prefix("# ").presence || path.dirname.basename.to_s.tr("-", " ").titleize
  end
end
