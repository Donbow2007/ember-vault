#!/usr/bin/env ruby
require "fileutils"
require "rbconfig"
require "json"

platform = ARGV.fetch(0)
output = File.expand_path(ARGV.fetch(1, File.join("dist", "ember-vault-#{platform}")))
root = File.expand_path("..", __dir__)
raise "Output must not contain the application source" if root == output || root.start_with?("#{output}/")
FileUtils.rm_rf(output)
FileUtils.mkdir_p(output)

exclude = %w[.git .bundle .gitignore dist storage log tmp test script node_modules vendor portable]
Dir.children(root).each do |name|
  next if exclude.include?(name) || name.start_with?(".env")
  FileUtils.cp_r(File.join(root, name), output, preserve: true)
end

FileUtils.mkdir_p(File.join(output, "portable"))
FileUtils.cp(File.join(root, "portable/start-linux.sh"), File.join(output, "portable/start-linux.sh"), preserve: true)
FileUtils.mkdir_p(File.join(output, "vendor"))
%w[map_indexer].each do |name|
  source = File.join(root, "vendor", name)
  destination = File.join(output, "vendor", name)
  FileUtils.cp_r(source, destination, preserve: true) if File.directory?(source)
end

Dir.glob(File.join(output, "config", "**", "*.key")).each { |path| FileUtils.rm_f(path) }

runtime = File.join(output, "runtime")
FileUtils.mkdir_p(runtime)

if platform == "linux-x64"
  staged_runtime = File.join(root, "portable", "runtime", "linux-x64")

  %w[ruby node llama].each do |name|
    source = File.join(staged_runtime, name)
    raise "Missing staged #{name} runtime: #{source}" unless File.directory?(source)

    destination = File.join(runtime, name)
    FileUtils.cp_r(source, destination, preserve: true)
  end
else
  raise "No staged runtime builder configured for #{platform}"
end

llama = File.join(runtime, "llama", "llama-server")
payload = "#{llama}.bin"
if File.file?(llama) && File.binread(llama, 4) == "\x7fELF"
  FileUtils.mv(llama, payload)
end
raise "Missing staged llama ELF payload" unless File.file?(payload)
FileUtils.cp(File.join(root, "portable/llama-server-linux.sh"), llama, preserve: true)
FileUtils.chmod(0o755, llama)

File.write(File.join(output, "BUILD_MANIFEST.json"), JSON.pretty_generate({
  ruby: "3.3.8", node: "22.22.0", llama: "v0.4.1",
  llama_commit: "b29c606e28a01b1bc8c1351026a0fa6e616bf6c4",
  platform: platform,
  build_baseline: "Ubuntu 22.04 / glibc 2.35 / GCC 11.4",
  cpu_features: [ "SSE4.2" ],
  disabled_cpu_features: %w[AVX AVX2 FMA F16C BMI2],
  ruby_source_sha256: "5ae28a87a59a3e4ad66bc2931d232dbab953d0aa8f6baf3bc4f8f80977c89cab"
}) + "\n")

FileUtils.mkdir_p(File.join(output, "storage"))
%w[models maps database settings logs backups tmp].each { |dir| FileUtils.mkdir_p(File.join(output, "storage", dir)) }

%w[bin/ember-vault portable/start-linux.sh].each do |relative|
  path = File.join(output, relative)
  FileUtils.chmod(0o755, path) if File.file?(path)
end

if ENV["EMBER_VAULT_CONTENT_DIR"]
  content = File.expand_path(ENV.fetch("EMBER_VAULT_CONTENT_DIR"))
  %w[models maps].each do |name|
    source = File.join(content, name)
    FileUtils.cp_r(Dir.glob(File.join(source, "*")), File.join(output, "storage", name), preserve: true) if Dir.exist?(source)
  end
end

gems = File.join(output, "runtime/ruby/lib/ruby/gems/3.3.0")
env = { "GEM_HOME" => gems, "GEM_PATH" => gems, "BUNDLE_PATH" => gems,
  "BUNDLE_GEMFILE" => File.join(output, "Gemfile"),
  "BUNDLE_IGNORE_CONFIG" => "1", "BUNDLE_WITHOUT" => "development:test",
  "RAILS_ENV" => "production", "SECRET_KEY_BASE" => "0" * 128,
  "EMBER_VAULT_BUNDLED_RUNTIME" => "1", "EMBER_VAULT_DATA_DIR" => File.join(output, "storage"),
  "BOOTSNAP_CACHE_DIR" => File.join(output, "storage/tmp/bootsnap"),
  "LD_LIBRARY_PATH" => File.join(output, "runtime/ruby/lib"),
  "PATH" => "#{output}/runtime/ruby/bin:#{output}/runtime/node/bin:/usr/bin:/bin" }
ruby = File.join(output, "runtime/ruby/bin/ruby")
raise "Asset precompilation failed" unless system(env, ruby, "bin/rails", "assets:precompile", chdir: output)
FileUtils.rm_rf(Dir.glob(File.join(output, "storage/tmp/*")))
FileUtils.rm_rf(File.join(output, "tmp"))
puts output
