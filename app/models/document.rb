class Document < ApplicationRecord
  STATUSES = %w[queued indexing ready failed deleting deletion_failed].freeze

  belongs_to :content_download, optional: true
  has_many :passages, dependent: :destroy

  validates :title, :original_filename, :content_type, :stored_path, :status, presence: true
  validates :status, inclusion: { in: STATUSES }

  after_destroy_commit :remove_stored_file

  def ready?
    status == "ready"
  end

  def deletion_progress
    return 0 if deletion_total.to_i.zero?

    (deletion_remaining.to_f / deletion_total * 100).ceil.clamp(0, 100)
  end

  def deleting?
    status == "deleting"
  end

  private

  def remove_stored_file
    path = EmberVault::Paths.resolve(stored_path)
    File.delete(path) if EmberVault::Paths.within?(path, EmberVault::Paths.archive_files) && File.file?(path)
  rescue ArgumentError
    nil
  end
end
