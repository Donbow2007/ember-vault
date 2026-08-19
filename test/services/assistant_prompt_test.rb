require "test_helper"

class AssistantPromptTest < ActiveSupport::TestCase
  test "requires grounded field guidance and adapts recipe structure" do
    document = Document.create!(title: "Cookbook", original_filename: "food.zim", content_type: "application/x-openzim",
      stored_path: "storage/content/zim/food.zim", byte_size: 100, status: "ready", passage_count: 1)
    passage = document.passages.create!(position: 0, heading: "Flatbread", body: "Mix flour and water.")
    source = ArchiveAnswer::Source.new(passage:, quote: passage.body, context: passage.body)
    prompt = AssistantPrompt.new(question: "How do I cook flatbread?", sources: [ source ])

    assert_match(/Answer only from the supplied SOURCE text/, prompt.system_instruction)
    assert_match(/INGREDIENTS, METHOD, TIMING/, prompt.user_prompt)
    assert_match(/\[1\] Cookbook — Flatbread/, prompt.user_prompt)
    assert_match(/field-ready answer with source citations/, prompt.user_prompt)
  end
end
