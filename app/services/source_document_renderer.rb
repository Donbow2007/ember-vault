class SourceDocumentRenderer
  ALLOWED_TAGS = %w[article section div p span h1 h2 h3 h4 h5 h6 ul ol li dl dt dd table thead tbody tr th td
    blockquote pre code strong b em i small figure figcaption img br hr].freeze
  ALLOWED_ATTRIBUTES = %w[src alt title width height colspan rowspan].freeze

  def initialize(document, passage, html)
    @document = document
    @passage = passage
    @fragment = Nokogiri::HTML.fragment(html.to_s.force_encoding("UTF-8"))
  end

  def call
    remove_unsafe_nodes
    rewrite_images
    selected = matching_section || @fragment
    ActionController::Base.helpers.sanitize(selected.to_html, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRIBUTES)
  end

  private

  def remove_unsafe_nodes
    @fragment.css("script, style, iframe, object, embed, form, input, button, link, meta").remove
  end

  def rewrite_images
    @fragment.css("img[src]").each do |image|
      path = local_path(image["src"])
      path ? image["src"] = Rails.application.routes.url_helpers.zim_asset_document_path(@document, path:) : image.remove
    end
  end

  def local_path(source)
    return if source.blank? || source.start_with?("data:") || source.match?(%r{\A[a-z][a-z0-9+.-]*:}i)

    clean_source = source.split(/[?#]/, 2).first.to_s
    base = Pathname(@passage.source_path.to_s).dirname
    resolved = (clean_source.start_with?("/") ? Pathname(clean_source.delete_prefix("/")) : base.join(clean_source)).cleanpath.to_s
    resolved unless resolved == ".." || resolved.start_with?("../")
  end

  def matching_section
    needle = normalized(@passage.body).first(80)
    return if needle.length < 20

    candidates = @fragment.css("p, li, td, blockquote, pre, section, article, div").select do |node|
      normalized(node.text).include?(needle)
    end
    match = candidates.min_by { |node| normalized(node.text).length }
    return unless match

    parent = match.parent
    parent && normalized(parent.text).length <= 12_000 ? parent : match
  end

  def normalized(text)
    text.to_s.gsub(/\s+/, " ").strip
  end
end
