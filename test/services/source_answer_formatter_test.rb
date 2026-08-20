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

    assert_match(/Do this:/, answer)
    assert_match(/1\. Cloudy water/, answer)
    assert_match(/2\. Bring the water to a rolling boil/, answer)
    assert_match(/One important limit/, answer)
    assert_match(/chemical pollutants/, answer)
  end

  test "uses a sourced chemical treatment when boiling is unavailable" do
    document = Document.create!(title: "Emergency Water Guide", original_filename: "water.pdf", content_type: "application/pdf",
      stored_path: "storage/archive_files/water.pdf", byte_size: 100, status: "ready", passage_count: 1)
    passage = document.passages.create!(position: 0, heading: "Chemical treatment", body: "Water treatment")
    quote = <<~TEXT
      Plain unscented household bleach (6% sodium hypochlorite) is the most practical way to purify a large quantity of water. Do not use scented bleaches, color safe bleaches, or bleaches with added cleaners.
      For adults, add 16 drops (1/8 teaspoon) of household bleach to each gallon of drinking water. Allow the water to sit for 30 minutes after adding the bleach before using it. If it still does not smell of bleach, discard it and find another source of water. This treatment is not safe for infants until it has been run through a good filter.
      Bleach will not remove chemical pollutants.
    TEXT
    source = ArchiveAnswer::Source.new(passage:, quote:, context: quote)

    answer = SourceAnswerFormatter.new(
      question: "How can I make questionable water safe to drink if I can't boil it?", sources: [ source ]).call

    assert_match(/Since boiling isn’t available/, answer)
    assert_match(/16 drops \(1\/8 teaspoon\)/, answer)
    assert_match(/stand for 30 minutes/, answer)
    assert_match(/not safe for infants/, answer)
    assert_match(/Do not use this method.*chemical/, answer)
    assert_no_match(/rolling boil|boil for/, answer)
  end

  test "turns a noisy forum passage into a concise conversational procedure" do
    document = Document.create!(title: "Gardening Questions", original_filename: "gardening.zim",
      content_type: "application/x-openzim", stored_path: "content/zim/gardening.zim", byte_size: 100,
      status: "ready", passage_count: 1)
    passage = document.passages.create!(position: 0,
      heading: "Is it possible to grow the corn kernels from commercial popcorn?", body: "Growing popcorn")
    quote = <<~TEXT
      Home Questions 20
      It doesn't seem like there's any process that would kill the kernels. So would it be possible to grow them?
      asked May 08 '13 at 01:20
      6 Answers6
      It is possible to grow plants from the kernels you get for making popcorn, but this corn is starchy rather than sweet.
      In essence, what they recommend is the following:
      Get plain, unflavoured popcorn kernels.
      Place the kernels between damp sheets of kitchen paper to germinate.
      The kernels that have germinated should then be planted in blocks and spaced roughly one foot apart.
      Keep watered in dry spells.
      Leave the ears on the plants until the surrounding leaves have browned.
      Bring the ears inside to dry further.
      Once fully dried, twist off the kernels for later use.
      answered May 08 '13 at 01:31
    TEXT
    source = ArchiveAnswer::Source.new(passage:, quote:, context: quote)

    answer = SourceAnswerFormatter.new(question: "How do I grow corn?", sources: [ source ]).call

    assert_match(/Yes—you can grow plants/, answer)
    assert_match(/Here’s how I’d approach it/, answer)
    assert_match(/1\. Start with plain/, answer)
    assert_match(/Place the kernels/, answer)
    assert_match(/Once fully dried/, answer)
    assert_no_match(/Home Questions|asked May|Answers6|answered May/, answer)
    assert_operator answer.length, :<, quote.length
    assert_equal [ passage.id ], SourceAnswerFormatter.cited_passage_ids(answer, [ source ])
  end

  test "summarizes nonprocedural sources instead of concatenating full passages" do
    document = Document.create!(title: "Corn Guide", original_filename: "corn.txt", content_type: "text/plain",
      stored_path: "archive_files/corn.txt", byte_size: 100, status: "ready", passage_count: 1)
    passage = document.passages.create!(position: 0, heading: "Corn Pollination", body: "Corn is wind pollinated")
    quote = "Corn is wind pollinated, so small plantings produce better ears when arranged in blocks. " \
      "This keeps plants close enough for pollen to reach neighboring silks. " \
      "Unrelated navigation text that should not become a long response."
    source = ArchiveAnswer::Source.new(passage:, quote:, context: quote)

    answer = SourceAnswerFormatter.new(question: "Why plant corn in blocks?", sources: [ source ]).call

    assert_match(/wind pollinated/, answer)
    assert_no_match(/Here’s what I found|clearest answer/, answer)
    assert_operator answer.length, :<, quote.length + 80
  end

  test "keeps only source passages actually cited by an answer" do
    document = Document.create!(title: "Field Guide", original_filename: "guide.txt", content_type: "text/plain",
      stored_path: "archive_files/guide.txt", byte_size: 100, status: "ready", passage_count: 2)
    first = document.passages.create!(position: 0, heading: "First", body: "First source")
    second = document.passages.create!(position: 1, heading: "Second", body: "Second source")
    sources = [ first, second ].map { |passage| ArchiveAnswer::Source.new(passage:, quote: passage.body, context: passage.body) }

    assert_equal [ second.id ], SourceAnswerFormatter.cited_passage_ids("Only the second fact is used. [2]", sources)
  end

  test "turns an unpunctuated recipe into a complete conversational answer" do
    document = Document.create!(title: "Field Cookbook", original_filename: "food.zim", content_type: "application/x-openzim",
      stored_path: "content/zim/food.zim", byte_size: 100, status: "ready", passage_count: 1)
    passage = document.passages.create!(position: 0, heading: "Tahini shortbread", body: "Recipe")
    quote = <<~TEXT
      This shortbread uses tahini and a small amount of sugar for a crisp result.
      Prep time: 15min
      Wait time: 1h
      Cook time: 15min
      Servings: 4
      IMPORTANT Keep the butter soft, not liquid, and chill the dough before baking.

      Ingredients
      125g of butter
      70g of sugar
      75g of tahini
      1 egg
      200g of flour

      Directions
      Thoroughly mix the egg, sugar and tahini
      Warm the butter until soft but not liquid
      Add the flour slowly
      Let the dough sit and cook it as described in the butter biscuit recipe
    TEXT
    source = ArchiveAnswer::Source.new(passage:, quote:, context: quote)

    answer = SourceAnswerFormatter.new(question: "How do I make tahini shortbread?", sources: [ source ]).call

    assert_match(/What you’ll need/, answer)
    assert_match(/• 125g of butter/, answer)
    assert_match(/Here’s how to make it/, answer)
    assert_match(/1\. Thoroughly mix/, answer)
    assert_match(/Plan on 15 minutes of prep, 1 hour of rest, and 15 minutes of cooking\. It makes 4 servings/, answer)
    assert_match(/The part to watch/, answer)
    assert_match(/I won’t guess/, answer)
  end

  test "explains when downloaded media has no searchable transcript" do
    document = Document.create!(title: "Offline Videos", original_filename: "videos.zim",
      content_type: "application/x-openzim", stored_path: "content/zim/videos.zim", byte_size: 100,
      status: "ready", passage_count: 1)
    passage = document.passages.create!(position: 0, heading: "NEW! 72 Hour Bug Out Bag", body: "NEW! 72 Hour Bug Out Bag")
    source = ArchiveAnswer::Source.new(passage:, quote: "72 Hour Bug Out Bag", context: "72 Hour Bug Out Bag")

    answer = SourceAnswerFormatter.new(question: "What should I pack in a 72-hour bag?", sources: [ source ]).call

    assert_match(/does not include searchable transcript/, answer)
    assert_match(/Open the source/, answer)
    assert_match(/\[1\]/, answer)
  end

  test "turns a diagnostic source into a concise checklist" do
    document = Document.create!(title: "Gardening Q&A", original_filename: "gardening.zim",
      content_type: "application/x-openzim", stored_path: "content/zim/gardening.zim", byte_size: 100,
      status: "ready", passage_count: 1)
    passage = document.passages.create!(position: 0, heading: "Tomato seedlings", body: "Troubleshooting")
    quote = "Here is what else you should check: Soil too compacted so roots can't expand. " \
      "Poor quality compost, such as too coarse and therefore not properly decomposed. " \
      "Compost is simply low in nitrogen. Low temperature or sunlight."
    source = ArchiveAnswer::Source.new(passage:, quote:, context: quote)

    answer = SourceAnswerFormatter.new(question: "How do I avoid common tomato seedling problems?", sources: [ source ]).call

    assert_match(/Check these first/, answer)
    assert_match(/Compacted soil can keep roots/, answer)
    assert_match(/Temperature or light may be too low/, answer)
  end

  test "summarizes the pressure-canning rule for low-acid vegetables" do
    document = Document.create!(title: "Canning", original_filename: "canning.pdf", content_type: "application/pdf",
      stored_path: "archive_files/canning.pdf", byte_size: 100, status: "ready", passage_count: 1)
    passage = document.passages.create!(position: 0, heading: "Low-acid foods", body: "Pressure canning")
    quote = "Vegetables are low acid. To control all risks of botulism, jars of these foods must be heat processed in a pressure canner, or acidified to a pH of 4.6 or lower before processing in boiling water."
    source = ArchiveAnswer::Source.new(passage:, quote:, context: quote)

    answer = SourceAnswerFormatter.new(question: "How can I safely preserve vegetables?", sources: [ source ]).call

    assert_match(/Most vegetables are low-acid foods/, answer)
    assert_match(/pressure canner/, answer)
    assert_match(/pH 4.6/, answer)
  end
end
