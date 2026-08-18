class SetupConfiguration < ApplicationRecord
  AI_PROFILES = %w[disabled source-assistant smollm2-135m].freeze
  THEMES = %w[dark light].freeze
  serialize :capabilities, coder: JSON, type: Array
  serialize :selected_resources, coder: JSON, type: Array

  validates :capabilities, :selected_resources, presence: true
  validates :ai_profile, inclusion: { in: AI_PROFILES }
  validates :theme, inclusion: { in: THEMES }
end
