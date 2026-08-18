class MapFeature < ApplicationRecord
  belongs_to :content_download

  validates :name, :category, :latitude, :longitude, presence: true
end
