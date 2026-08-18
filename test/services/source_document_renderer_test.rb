require "test_helper"

class SourceDocumentRendererTest < ActiveSupport::TestCase
  test "keeps the matching original section and rewrites local images" do
    document = Document.new(id: 42)
    passage = Passage.new(body: "Boil flood water before drinking it.", source_path: "guides/water.html")
    html = <<~HTML
      <script>alert('unsafe')</script>
      <section><p>Boil flood water before drinking it.</p><img src="../images/boil.jpg" onerror="alert(1)"></section>
      <img src="https://outside.example/tracker.png">
    HTML

    rendered = SourceDocumentRenderer.new(document, passage, html).call

    assert_includes rendered, "Boil flood water"
    assert_includes rendered, "/documents/42/zim_asset?path=images%2Fboil.jpg"
    assert_not_includes rendered, "script"
    assert_not_includes rendered, "onerror"
    assert_not_includes rendered, "outside.example"
  end
end
