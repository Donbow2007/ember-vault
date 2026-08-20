require "test_helper"

class AssistantPromptTest < ActiveSupport::TestCase
  test "requires grounded field guidance and adapts recipe structure" do
    document = Document.create!(title: "Cookbook", original_filename: "food.zim", content_type: "application/x-openzim",
      stored_path: "storage/content/zim/food.zim", byte_size: 100, status: "ready", passage_count: 1)
    passage = document.passages.create!(position: 0, heading: "Flatbread", body: "Mix flour and water.")
    source = ArchiveAnswer::Source.new(passage:, quote: passage.body, context: passage.body)
    prompt = AssistantPrompt.new(question: "How do I cook flatbread?", sources: [ source ])

    assert_match(/Answer only from SOURCE/, prompt.system_instruction)
    assert_match(/INGREDIENTS, METHOD, TIMING/, prompt.user_prompt)
    assert_match(/\[1\] Cookbook — Flatbread/, prompt.user_prompt)
    assert_match(/natural, practical voice/, prompt.user_prompt)
    assert_match(/experienced older brother/, prompt.system_instruction)
  end

  test "sends the model only the most relevant compact source" do
    document = Document.create!(title: "Garden Guide", original_filename: "garden.zim", content_type: "application/x-openzim",
      stored_path: "content/zim/garden.zim", byte_size: 100, status: "ready", passage_count: 2)
    shrubs = document.passages.create!(position: 0, heading: "Shrubs", body: "Plant shrubs in a straight hedge.")
    corn = document.passages.create!(position: 1, heading: "Corn Pollination",
      body: "Plant corn in blocks because corn is wind pollinated and single rows may leave missing kernels.")
    sources = [ shrubs, corn ].map { |passage| ArchiveAnswer::Source.new(passage:, quote: passage.body, context: passage.body) }
    prompt = AssistantPrompt.new(question: "Why plant corn in blocks?", sources:)

    assert_match(/Corn Pollination/, prompt.user_prompt)
    assert_no_match(/Plant shrubs/, prompt.user_prompt)
    assert_equal 2, prompt.primary_citation
    assert_equal 2, prompt.citation_for("Wind pollination can leave missing kernels.")
    assert_operator prompt.completion_prompt.length, :<, 2_000
  end
end
