#!/usr/bin/env ruby
require_relative "../config/environment"
require "benchmark"
require "json"

QUESTIONS = [
  "How can I make questionable water safer to drink in an emergency?",
  "What are the warning signs of hypothermia and what should I do first?",
  "How do I preserve food safely during a multi-day power outage?",
  "How can I navigate with a paper map and compass?",
  "How should I prioritize shelter, water, fire, and food if stranded?",
  "What sanitation setup reduces illness when plumbing is unavailable?",
  "How do I safely run a portable generator during an outage?",
  "What information should I include in an emergency radio message?",
  "How can I store garden seeds for future planting?",
  "What should a basic evacuation bag contain?"
].freeze

entry = ModelCatalog.find(ARGV.first) || ModelCatalog.default
abort "Install #{entry.display_name} first." unless ModelCatalog.model_path(entry).file?

runtime = LocalAiRuntime.new(profile: entry.id)
results = QUESTIONS.map do |question|
  answer = nil
  elapsed = Benchmark.realtime { answer = runtime.generate(AssistantPrompt.new(question:)) }
  { question:, seconds: elapsed.round(2), answer: }
end

output = {
  model: entry.id,
  generated_at: Time.current.iso8601,
  average_seconds: (results.sum { |result| result[:seconds] } / results.length).round(2),
  results:
}
path = EmberVault::PortableStorage.path("logs", "benchmark-#{entry.id}-#{Time.now.utc.strftime("%Y%m%dT%H%M%SZ")}.json")
FileUtils.mkdir_p(path.dirname)
path.write(JSON.pretty_generate(output))
puts path
