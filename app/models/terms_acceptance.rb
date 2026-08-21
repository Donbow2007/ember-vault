class TermsAcceptance < ApplicationRecord
  validates :terms_version, :accepted_at, :application_version, presence: true

  def self.current?(terms = TermsDocument.new)
    exists?(terms_version: terms.version)
  end

  def self.accept_current!(terms = TermsDocument.new)
    find_or_create_by!(terms_version: terms.version) do |acceptance|
      acceptance.accepted_at = Time.current
      acceptance.application_version = TermsDocument.application_version
    end
  end
end
