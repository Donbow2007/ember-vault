class MapFeature < ApplicationRecord
  belongs_to :map_pack

  validates :name, :category, :latitude, :longitude, presence: true
end
