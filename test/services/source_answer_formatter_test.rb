require "test_helper"

class SourceAnswerFormatterTest < ActiveSupport::TestCase
  test "turns sourced water treatment facts into concise field steps" do
    document = Document.create!(title: "Emergency Water Guide", original_filename: "water.pdf", content_type: "application/pdf",
      stored_path: "storage/archive_files/water.pdf", byte_size: 100, status: "ready", passage_count: 1)
    passage = document.passages.create!(position: 0, heading: "Purifying by boiling", body: "Water treatment")
    quote = <<~TEXT
      Cloudy water should be filtered before boiling.
      Bring the water to a rolling boil for at least one full minute.
      Let the water cool before drinking.
      Caution: Many chemical pollutants will not be removed by boiling.
    TEXT
    source = ArchiveAnswer::Source.new(passage:, quote:, context: quote)

    answer = SourceAnswerFormatter.new(question: "How can I make water safe to drink?", sources: [ source ]).call

    assert_match(/STEPS/, answer)
    assert_match(/1\. Cloudy water/, answer)
    assert_match(/2\. Bring the water to a rolling boil/, answer)
    assert_match(/IMPORTANT LIMIT/, answer)
    assert_match(/chemical pollutants/, answer)
  end
end
