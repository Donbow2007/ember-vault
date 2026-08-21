require "json"

class TermsDocument
  PATH = Rails.root.join("config", "legal", "terms.json")

  attr_reader :attributes

  def initialize(path: PATH)
    @attributes = JSON.parse(path.read)
  end

  delegate :fetch, to: :attributes

  def version = fetch("version")
  def last_updated = Date.iso8601(fetch("last_updated"))
  def title = fetch("title")
  def sections = fetch("sections")
  def acceptance_label = fetch("acceptance_label")

  def self.application_version
    Rails.root.join("VERSION").read.strip
  rescue Errno::ENOENT
    "development"
  end
end
