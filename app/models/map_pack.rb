class MapPack < ApplicationRecord
  has_many :map_features, dependent: :delete_all

  validates :title, :stored_path, presence: true
  validates :stored_path, uniqueness: true

  def pack_path
    root = EmberVault::PortableStorage.path("maps").expand_path
    path = EmberVault::PortableStorage.root.join(stored_path).expand_path
    raise ArgumentError, "Map pack path is outside portable map storage" unless path.to_s.start_with?("#{root}#{File::SEPARATOR}")

    path
  end

  alias_method :archive_path, :pack_path
end
