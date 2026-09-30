#!/usr/bin/env ruby
require "fileutils"
require "rbconfig"

platform = ARGV.fetch(0)
output = ARGV.fetch(1, File.join("dist", "ember-vault-#{platform}"))
root = File.expand_path("..", __dir__)
FileUtils.rm_rf(output)
FileUtils.mkdir_p(output)

exclude = %w[.git dist storage log tmp test node_modules]
Dir.children(root).each do |name|
  next if exclude.include?(name)
  FileUtils.cp_r(File.join(root, name), output, preserve: true)
end

runtime = File.join(output, "runtime")
FileUtils.mkdir_p(runtime)
ruby_prefix = RbConfig::CONFIG.fetch("prefix")
FileUtils.mkdir_p(File.join(runtime, "ruby"))
FileUtils.cp_r(Dir.glob(File.join(ruby_prefix, "*")), File.join(runtime, "ruby"), preserve: true)

FileUtils.mkdir_p(File.join(output, "storage"))
%w[models maps database settings logs backups tmp].each { |dir| FileUtils.mkdir_p(File.join(output, "storage", dir)) }

puts output
