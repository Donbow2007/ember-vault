class MapPack < ApplicationRecord
  has_many :map_features, dependent: :delete_all

  validates :title, :stored_path, presence: true

  def archive_path
    root = Pathname.new(ENV.fetch("EMBER_VAULT_DATA_DIR", Rails.root.join("storage").to_s)).expand_path.cleanpath
    path = root.join(stored_path).cleanpath
    maps_root = root.join("maps").cleanpath
    raise ArgumentError, "Map pack path is outside portable map storage" unless path.to_s.start_with?("#{maps_root}#{File::SEPARATOR}")

    path
  end
end
