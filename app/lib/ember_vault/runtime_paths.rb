module EmberVault
  module RuntimePaths
    module_function

    def executable(name, root: File.expand_path("../..", __dir__))
      relative = { "ruby" => "ruby/bin/ruby", "node" => "node/bin/node", "llama-server" => "llama/llama-server" }.fetch(name)
      relative += ".exe" if Gem.win_platform?
      bundled = File.join(root, "runtime", relative)
      if ENV["EMBER_VAULT_BUNDLED_RUNTIME"] == "1"
        raise "Missing executable bundled #{name}: #{bundled}" unless File.file?(bundled) && File.executable?(bundled)
        return bundled
      end
      override = ENV[name == "llama-server" ? "LLAMA_SERVER_PATH" : "EMBER_VAULT_#{name.upcase}_BIN"]
      return override unless override.to_s.empty?
      staged = File.join(root, "portable/runtime/linux-x64", relative)
      return staged if RUBY_PLATFORM.include?("linux") && File.file?(staged) && File.executable?(staged)
      return bundled if File.file?(bundled) && File.executable?(bundled)
      name
    end
  end
end
