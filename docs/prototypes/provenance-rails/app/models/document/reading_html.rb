# Renders the body for readers: every mark except provenance, which is
# editorial data and never reaches the page. Citations become <cite> elements
# carrying their OSIS reference for links or tooltips.
class Document::ReadingHtml
  include ActionView::Helpers::TagHelper

  BLOCK_TAGS = {
    "paragraph" => :p, "bulletList" => :ul, "orderedList" => :ol, "listItem" => :li, "blockquote" => :blockquote
  }.freeze

  MARK_TAGS = { "bold" => :strong, "italic" => :em, "strike" => :s, "underline" => :u, "code" => :code }.freeze

  def initialize(content)
    @content = content
  end

  def to_html
    render_children(@content.json)
  end

  private
    def render_children(node)
      safe_join(Array(node["content"]).map { |child| render(child) })
    end

    def render(node)
      attrs = node["attrs"] || {}

      case node["type"]
      when "text" then render_text(node)
      when "hardBreak" then tag.br
      when "horizontalRule" then tag.hr
      when "heading" then content_tag("h#{attrs["level"].to_i.clamp(1, 6)}", render_children(node))
      when "orderedList" then content_tag(:ol, render_children(node), start: (attrs["start"] if attrs["start"].to_i > 1))
      when "codeBlock" then tag.pre(tag.code(node["content"].to_a.sum("") { |child| child["text"].to_s }, class: ("language-#{attrs["language"]}" if attrs["language"].present?)))
      else content_tag(BLOCK_TAGS.fetch(node["type"]), render_children(node))
      end
    end

    def render_text(node)
      Array(node["marks"]).reverse.reduce(ERB::Util.html_escape(node["text"])) do |html, mark|
        attrs = mark["attrs"] || {}

        case mark["type"]
        when "provenance" then html
        when "bibleRef" then tag.cite(html, class: "bible-ref", data: { osis: attrs["osis"] })
        when "link" then tag.a(html, href: attrs["href"], rel: "noopener noreferrer nofollow")
        else content_tag(MARK_TAGS.fetch(mark["type"]), html)
        end
      end
    end
end
