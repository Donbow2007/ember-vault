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
    path = EmberVault::Paths.resolve(stored_path)
    File.delete(path) if EmberVault::Paths.within?(path, EmberVault::Paths.archive_files) && File.file?(path)
    Passage.rebuild_search_index
  rescue ArgumentError
    Passage.rebuild_search_index
  end
end
