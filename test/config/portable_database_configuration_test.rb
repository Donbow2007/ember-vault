require "test_helper"
require "erb"
require "yaml"

class PortableDatabaseConfigurationTest < ActiveSupport::TestCase
  test "portable databases use the selected drive with durable low-memory pragmas" do
    original_path = ENV["EMBER_VAULT_DATA_PATH"]
    original_portable = ENV["EMBER_VAULT_PORTABLE"]
    ENV["EMBER_VAULT_DATA_PATH"] = "/portable/ember-vault/data"
    ENV["EMBER_VAULT_PORTABLE"] = "1"

    rendered = ERB.new(Rails.root.join("config/database.yml").read).result
    configuration = YAML.safe_load(rendered, aliases: true)
    defaults = configuration.fetch("default")

    assert_equal "/portable/ember-vault/data/production.sqlite3", configuration.dig("production", "primary", "database")
    assert_equal "wal", defaults.dig("pragmas", "journal_mode")
    assert_equal "full", defaults.dig("pragmas", "synchronous")
    assert_equal 33_554_432, defaults.dig("pragmas", "mmap_size")
  ensure
    ENV["EMBER_VAULT_DATA_PATH"] = original_path
    ENV["EMBER_VAULT_PORTABLE"] = original_portable
  end
end
