#!/usr/bin/env ruby
require "fileutils"

root = File.expand_path(ARGV.fetch(0, File.join(__dir__, "..")))
required = %w[models maps database settings logs backups tmp]
errors = []

required.each do |name|
  path = File.join(root, "storage", name)
  errors << "missing storage/#{name}" unless Dir.exist?(path)
end

ruby = Gem.win_platform? ? File.join(root, "runtime", "ruby", "bin", "ruby.exe") : File.join(root, "runtime", "ruby", "bin", "ruby")
llama = Gem.win_platform? ? File.join(root, "runtime", "llama", "llama-server.exe") : File.join(root, "runtime", "llama", "llama-server")
errors << "missing bundled Ruby" unless File.file?(ruby)
errors << "missing bundled llama-server" unless File.file?(llama)
errors << "missing production gems" unless Dir.exist?(File.join(root, "vendor", "bundle"))
errors << "missing map indexer dependencies" unless Dir.exist?(File.join(root, "vendor", "map_indexer", "node_modules"))
errors << "missing precompiled assets" unless Dir.exist?(File.join(root, "public", "assets"))

if errors.any?
  warn errors.join("\n")
  exit 1
end

puts "Portable bundle structure validated."
