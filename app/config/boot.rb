if ENV["EMBER_VAULT_DATA_DIR"]
  ENV["BOOTSNAP_CACHE_DIR"] ||= File.join(ENV["EMBER_VAULT_DATA_DIR"], "tmp", "bootsnap")
  ENV["TMPDIR"] ||= File.join(ENV["EMBER_VAULT_DATA_DIR"], "tmp")
end

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.
require "bootsnap/setup" # Speed up boot time by caching expensive operations.
