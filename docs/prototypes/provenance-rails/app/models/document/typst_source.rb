# Turns the body into Typst markup for print. Every run of text is emitted as
# a Typst string literal (#"..."), so nothing a reader typed can be read as
# markup: only backslashes and quotes need escaping. Styling lives in the
# template (app/views/documents/print.typ), which defines `bibleref`.
class Document::TypstSource
  def self.string(value)
    %("#{value.to_s.gsub(/[\\"]/) { |char| "\\#{char}" }}")
  end

  def initialize(content)
    @content = content
  end

  def to_s
    blocks(@content.json)
  end

  private
    def blocks(node)
      Array(node["content"]).map { |child| block(child) }.join("\n\n")
    end

    def block(node)
      attrs = node["attrs"] || {}

      case node["type"]
      when "paragraph" then inline(node)
      when "heading" then "#heading(level: #{attrs["level"].to_i.clamp(1, 6)})[#{inline(node)}]"
      when "bulletList" then "#list(#{items(node)})"
      when "orderedList" then "#enum(start: #{[ attrs["start"].to_i, 1 ].max}, #{items(node)})"
      when "blockquote" then "#quote(block: true)[#{blocks(node)}]"
      when "codeBlock" then "#raw(#{string(code_text(node))}, block: true#{", lang: #{string(attrs["language"])}" if attrs["language"].present?})"
      when "horizontalRule" then "#line(length: 100%)"
      else raise ArgumentError, "no Typst rendering for #{node["type"]}"
      end
    end

    def items(node)
      Array(node["content"]).map { |item| "[#{blocks(item)}]" }.join(", ")
    end

    def inline(node)
      Array(node["content"]).map { |child| child["type"] == "hardBreak" ? "#linebreak()" : text(child) }.join
    end

    def text(node)
      Array(node["marks"]).reverse.reduce("##{string(node["text"])}") do |markup, mark|
        attrs = mark["attrs"] || {}

        case mark["type"]
        when "provenance" then markup
        when "bold" then "#strong[#{markup}]"
        when "italic" then "#emph[#{markup}]"
        when "strike" then "#strike[#{markup}]"
        when "underline" then "#underline[#{markup}]"
        when "code" then "#raw(#{string(node["text"])})"
        when "link" then "#link(#{string(attrs["href"])})[#{markup}]"
        when "bibleRef" then "#bibleref(#{string(attrs["osis"])})[#{markup}]"
        else raise ArgumentError, "no Typst rendering for mark #{mark["type"]}"
        end
      end
    end

    def code_text(node)
      Array(node["content"]).sum("") { |child| child["text"].to_s }
    end

    def string(value)
      self.class.string(value)
    end
end
