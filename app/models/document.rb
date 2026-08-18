class Document < ApplicationRecord
  belongs_to :content_download, optional: true
  has_many :passages, dependent: :destroy

  validates :title, :original_filename, :content_type, :stored_path, :status, presence: true
  validates :status, inclusion: { in: %w[queued indexing ready failed] }

  after_destroy_commit :remove_stored_file

  def ready?
    status == "ready"
  end

  private

  def remove_stored_file
    path = Rails.root.join(stored_path).cleanpath
    archive_root = Rails.root.join("storage", "archive_files").cleanpath
    File.delete(path) if path.to_s.start_with?("#{archive_root}/") && File.file?(path)
    Passage.rebuild_search_index
  end
end
