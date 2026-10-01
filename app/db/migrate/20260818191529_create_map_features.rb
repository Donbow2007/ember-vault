class CreateMapFeatures < ActiveRecord::Migration[8.0]
  def change
    # Ember Vault 2 creates map_features with map_packs in the replacement migration.
    # This migration intentionally remains empty so existing migration versions stay valid.
  end
end
