class MapPack < ApplicationRecord
  STATUSES = %w[queued downloading complete failed].freeze

  has_many :map_features, dependent: :delete_all

  validates :title, :stored_path, presence: true
  validates :stored_path, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :catalog_id, uniqueness: true, allow_blank: true

  def progress
    return 100 if status == "complete"
    return 0 if expected_bytes.to_i.zero?

    [ (downloaded_bytes.to_f / expected_bytes * 100).round, 100 ].min
  end

  def installed?
    status == "complete" && pack_path.file?
  rescue ArgumentError
    false
  end

  def pack_path
    root = EmberVault::PortableStorage.path("maps").expand_path
    path = EmberVault::PortableStorage.root.join(stored_path).expand_path
    raise ArgumentError, "Map pack path is outside portable map storage" unless path.to_s.start_with?("#{root}#{File::SEPARATOR}")

    path
  end

  alias_method :archive_path, :pack_path
end
