require "test_helper"

class ArchiveAnswerTest < ActiveSupport::TestCase
  setup do
    @document = Document.create!(title: "Water Safety", original_filename: "water.txt", content_type: "text/plain",
      stored_path: "storage/archive_files/water.txt", byte_size: 100, status: "ready", passage_count: 1)
    @passage = @document.passages.create!(position: 0, heading: "Flood Water",
      body: "Flood water may contain dangerous organisms. Boil clear water for one minute before drinking it. Store treated water in a clean covered container.")
    Passage.rebuild_search_index
  end

  test "extracts a relevant sentence and retains its source" do
    answer = ArchiveAnswer.new("How should I boil water after a flood?").call

    assert answer.found?
    assert_equal @passage, answer.sources.first.passage
    assert_match(/Boil clear water/, answer.sources.first.quote)
  end

  test "does not invent an answer without a matching passage" do
    answer = ArchiveAnswer.new("repair a diesel generator").call

    assert_not answer.found?
    assert_empty answer.sources
  end

  test "returns a complete multi-passage recipe without unrelated filler" do
    recipe = Document.create!(title: "Offline Cookbook", original_filename: "food.zim", content_type: "application/x-openzim",
      stored_path: "storage/content/zim/food.zim", byte_size: 100, status: "ready", passage_count: 4)
    recipe.passages.create!(position: 10, heading: "Tahini short bread",
      body: "Tahini short bread Home Back This short bread recipe uses sesame paste called Tahini.")
    recipe.passages.create!(position: 11, heading: "Tahini short bread", body: "Ingredients")
    recipe.passages.create!(position: 12, heading: "Tahini short bread", body: "125g butter\n75g Tahini\n1 egg\n200g flour")
    recipe.passages.create!(position: 13, heading: "Tahini short bread",
      body: "Directions\nMix the egg, sugar and Tahini. Add the flour slowly. Bake until crisp.")
    unrelated = Document.create!(title: "Weather", original_filename: "weather.txt", content_type: "text/plain",
      stored_path: "storage/archive_files/weather.txt", byte_size: 100, status: "ready", passage_count: 1)
    unrelated.passages.create!(position: 0, heading: "Making Snow", body: "Making snow with boiling water.")
    Passage.rebuild_search_index

    answer = ArchiveAnswer.new("How do I make Tahini short bread?").call

    assert_equal 1, answer.sources.size
    assert_match(/125g butter/, answer.sources.first.quote)
    assert_match(/Mix the egg/, answer.sources.first.quote)
    assert_no_match(/Making snow/, answer.sources.first.quote)
  end
end
