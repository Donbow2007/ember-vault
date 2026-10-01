#!/usr/bin/env ruby
require "fileutils"
require "rbconfig"

platform = ARGV.fetch(0)
output = ARGV.fetch(1, File.join("dist", "ember-vault-#{platform}"))
root = File.expand_path("..", __dir__)
FileUtils.rm_rf(output)
FileUtils.mkdir_p(output)

exclude = %w[.git dist storage log tmp test node_modules vendor]
Dir.children(root).each do |name|
  next if exclude.include?(name)
  FileUtils.cp_r(File.join(root, name), output, preserve: true)
end

FileUtils.mkdir_p(File.join(output, "vendor"))
%w[bundle map_indexer].each do |name|
  source = File.join(root, "vendor", name)
  destination = File.join(output, "vendor", name)
  FileUtils.cp_r(source, destination, preserve: true) if File.directory?(source)
end

runtime = File.join(output, "runtime")
FileUtils.mkdir_p(runtime)

ruby_bindir = RbConfig::CONFIG.fetch("bindir")
ruby_libdir = RbConfig::CONFIG.fetch("rubylibdir")
ruby_archdir = RbConfig::CONFIG.fetch("archdir")

ruby_runtime = File.join(runtime, "ruby")
FileUtils.mkdir_p(File.join(ruby_runtime, "bin"))
%w[ruby bundle gem erb irb rake].each do |name|
  source = File.join(ruby_bindir, name)
  FileUtils.cp(source, File.join(ruby_runtime, "bin", name), preserve: true) if File.file?(source)
end

FileUtils.mkdir_p(File.join(ruby_runtime, "lib"))
%w[ruby x86_64-linux-gnu].each do |name|
  target = File.join(ruby_runtime, "lib", name)
  FileUtils.mkdir_p(target)
end

FileUtils.cp_r(File.join(ruby_libdir, "."), File.join(ruby_runtime, "lib", "ruby"), preserve: true)
FileUtils.cp_r(File.join(ruby_archdir, "."), File.join(ruby_runtime, "lib", "x86_64-linux-gnu", "ruby"), preserve: true)
Dir.glob("/lib/x86_64-linux-gnu/libruby-*.so*").each do |library|
  FileUtils.cp(library, File.join(ruby_runtime, "lib", "x86_64-linux-gnu"), preserve: true)
end

node_bin = ENV["EMBER_VAULT_NODE_BIN"] || "/usr/bin/node"
if File.file?(node_bin)
  FileUtils.mkdir_p(File.join(runtime, "node", "bin"))
  FileUtils.cp(node_bin, File.join(runtime, "node", "bin", "node"), preserve: true)
  FileUtils.mkdir_p(File.join(runtime, "node", "lib"))
  Dir.glob("/lib/x86_64-linux-gnu/libnode.so*").each do |library|
    FileUtils.cp(library, File.join(runtime, "node", "lib"), preserve: true)
  end
end

llama_server = ENV["EMBER_VAULT_LLAMA_SERVER"] || File.join(root, "vendor", "llama.cpp", "build", "bin", "llama-server")
if File.file?(llama_server)
  FileUtils.mkdir_p(File.join(runtime, "llama"))
  FileUtils.cp(llama_server, File.join(runtime, "llama", "llama-server"), preserve: true)
end

FileUtils.mkdir_p(File.join(output, "storage"))
%w[models maps database settings logs backups tmp].each { |dir| FileUtils.mkdir_p(File.join(output, "storage", dir)) }

%w[bin/ember-vault portable/start-linux.sh].each do |relative|
  path = File.join(output, relative)
  FileUtils.chmod(0o755, path) if File.file?(path)
end

puts output
