#!/usr/bin/env ruby
require "open3"
root = File.expand_path(ARGV.fetch(0))
errors = []
%w[models maps database settings logs backups tmp].each do |name|
  errors << "missing storage/#{name}" unless Dir.exist?(File.join(root, "storage", name))
end
%w[ruby/bin/ruby node/bin/node llama/llama-server].each do |relative|
  path = File.join(root, "runtime", relative)
  errors << "missing executable #{relative}" unless File.executable?(path)
end
%w[vendor/map_indexer/node_modules public/assets runtime/ruby/lib/ruby/gems/3.3.0].each do |relative|
  errors << "missing #{relative}" unless Dir.exist?(File.join(root, relative))
end
%w[tmp/local_secret.txt storage/.secret_key_base storage/ember-vault.pid].each do |relative|
  errors << "generated state must not ship: #{relative}" if File.exist?(File.join(root, relative))
end
errors << "generated databases must not ship" unless Dir.glob(File.join(root, "storage", "**", "*.sqlite3*")).empty?
%w[runtime/node/lib/libstdc++.so.6 runtime/node/lib/libgcc_s.so.1 runtime/llama/lib/libvulkan.so.1 runtime/llama/compat/libstdc++.so.6 runtime/llama/compat/libgcc_s.so.1 bin/portable-server].each do |relative|
  errors << "missing bundled dependency #{relative}" unless File.file?(File.join(root, relative))
end
launcher = File.join(root, "portable/start-linux.sh")
errors << "missing executable launcher" unless File.executable?(launcher)
Dir.glob(File.join(root, "{app,config,lib,bin,script,portable}", "**", "*")).each do |path|
  next unless File.file?(path)
  errors << "developer path in #{path}" if File.binread(path).match?(%r{/home/donnell|/tmp/ember-vault-llama})
end
abort errors.join("\n") unless errors.empty?
env = { "RUBYLIB" => nil, "RUBYOPT" => nil, "BUNDLE_GEMFILE" => File.join(root, "Gemfile"), "PATH" => "#{root}/runtime/ruby/bin:#{root}/runtime/node/bin:/usr/bin:/bin",
  "LD_LIBRARY_PATH" => "#{root}/runtime/llama/lib:#{root}/runtime/ruby/lib",
  "GEM_HOME" => "#{root}/runtime/ruby/lib/ruby/gems/3.3.0",
  "GEM_PATH" => "#{root}/runtime/ruby/lib/ruby/gems/3.3.0",
  "BUNDLE_PATH" => "#{root}/runtime/ruby/lib/ruby/gems/3.3.0",
  "BUNDLE_WITHOUT" => "development:test", "BUNDLE_IGNORE_CONFIG" => "1" }
commands = [
  ["#{root}/runtime/ruby/bin/ruby", "-e", 'abort RUBY_VERSION unless RUBY_VERSION == "3.3.8"; %w[zlib openssl psych fiddle readline].each { |x| require x }'],
  ["#{root}/runtime/ruby/bin/ruby", "#{root}/runtime/ruby/bin/bundle", "check"],
  ["#{root}/runtime/node/bin/node", "--version"],
  ["#{root}/runtime/llama/llama-server", "--version"]
]
commands.each do |command|
  output, status = Open3.capture2e(env, *command, chdir: root)
  errors << "#{command.join(' ')} failed: #{output}" unless status.success?
  errors << "wrong Node version: #{output}" if command.first.end_with?("/node") && output.strip != "v22.22.0"
  errors << "wrong llama version: #{output}" if command.first.end_with?("/llama-server") && !(output.include?("version: 0.4.1") && output.include?("commit b29c606"))
end
Dir.glob(File.join(root, "runtime", "**", "*")).each do |path|
  next unless File.file?(path) && File.binread(path, 4) == "\x7fELF"
  errors << "developer path in #{path}" if File.binread(path).match?(%r{/home/donnell|/tmp/ember-vault-llama})
  versions, = Open3.capture2e("readelf", "--version-info", path)
  required = versions.scan(/Name: GLIBC_(\d+)\.(\d+)/).map { |major, minor| [major.to_i, minor.to_i] }.max
  errors << "GLIBC newer than 2.35 required by #{path}: #{required.join('.')}" if required && (required <=> [2, 35]) == 1
  output, = Open3.capture2e(env, "ldd", path)
  errors << "missing shared library for #{path}: #{output}" if output.include?("not found")
end
abort errors.join("\n") unless errors.empty?
puts "Portable executable, dependency, gem and structure checks passed."
