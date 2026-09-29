# The ProseMirror JSON a document is stored as, and everything the server
# derives from it. Offsets are UTF-16 code units, the unit JavaScript strings
# and ProseMirror positions use, so rows indexed here line up with the editor.
class Document::Body
  TEXTBLOCKS = %w[ paragraph heading codeBlock ].freeze

  NODES = {
    "doc" => [],
    "paragraph" => [],
    "heading" => %w[ level ],
    "bulletList" => [],
    "orderedList" => %w[ start type ],
    "listItem" => [],
    "blockquote" => [],
    "codeBlock" => %w[ language ],
    "horizontalRule" => [],
    "hardBreak" => [],
    "text" => []
  }.freeze

  MARKS = {
    "bold" => [],
    "italic" => [],
    "strike" => [],
    "underline" => [],
    "code" => [],
    "link" => %w[ href target rel class title ],
    "bibleRef" => %w[ osis ],
    "provenance" => %w[ origin run by session ]
  }.freeze

  ORIGINS = %w[ tesseract llm human ].freeze
  MAX_DEPTH = 32

  Block = Data.define(:index, :type, :pos, :text, :marks)
  Mark = Data.define(:type, :attrs, :start, :end)

  attr_reader :json

  def initialize(json)
    @json = json.is_a?(String) ? JSON.parse(json) : json.deep_stringify_keys
  end

  def errors
    @errors ||= [].tap { |errors| validate(json, errors, depth: 0) }
  end

  def blocks
    @blocks ||= [].tap { |blocks| collect_blocks(json, 0, blocks) }
  end

  def plain_text
    blocks.map(&:text).join("\n\n")
  end

  def self.utf16_length(string)
    string.encode("UTF-16LE").bytesize / 2
  end

  def self.utf16_slice(string, from, to)
    string.encode("UTF-16LE").byteslice(from * 2, (to - from) * 2).encode("UTF-8")
  end

  private
    def validate(node, errors, depth:)
      return errors << "document nests deeper than #{MAX_DEPTH}" if depth > MAX_DEPTH
      return errors << "node must be an object" unless node.is_a?(Hash)

      type = node["type"]
      allowed_attrs = NODES[type]
      return errors << "unknown node type #{type.inspect}" unless allowed_attrs

      unknown = (node["attrs"] || {}).keys - allowed_attrs
      errors << "#{type} has unknown attrs #{unknown.join(", ")}" if unknown.any?

      if type == "text"
        errors << "text node without text" unless node["text"].is_a?(String) && node["text"].present?
        Array(node["marks"]).each { |mark| validate_mark(mark, errors) }
      else
        Array(node["content"]).each { |child| validate(child, errors, depth: depth + 1) }
      end
    end

    def validate_mark(mark, errors)
      type = mark["type"]
      allowed_attrs = MARKS[type]
      return errors << "unknown mark type #{type.inspect}" unless allowed_attrs

      attrs = mark["attrs"] || {}
      unknown = attrs.keys - allowed_attrs
      errors << "#{type} mark has unknown attrs #{unknown.join(", ")}" if unknown.any?

      case type
      when "provenance"
        errors << "unknown provenance origin #{attrs["origin"].inspect}" unless ORIGINS.include?(attrs["origin"])
      when "bibleRef"
        errors << "invalid citation #{attrs["osis"].inspect}" unless Osis.valid?(attrs["osis"])
      when "link"
        errors << "unsafe link #{attrs["href"].inspect}" unless safe_href?(attrs["href"])
      end
    end

    def safe_href?(href)
      URI.parse(href.to_s).scheme.in?(%w[ http https mailto ])
    rescue URI::InvalidURIError
      false
    end

    # Walks the tree tracking ProseMirror positions: text counts its UTF-16
    # length, inline leaves count 1, and every other node adds an open and a
    # close token around its content.
    def collect_blocks(node, pos, blocks)
      if TEXTBLOCKS.include?(node["type"])
        blocks << textblock(node, pos, blocks.size)
        return node_size(node)
      end

      content_pos = node["type"] == "doc" ? pos : pos + 1
      Array(node["content"]).each { |child| content_pos += collect_blocks(child, content_pos, blocks) }
      node_size(node)
    end

    def textblock(node, pos, index)
      text = +""
      marks = []
      Array(node["content"]).each do |child|
        piece = inline_text(child)
        start = Document::Body.utf16_length(text)
        text << piece
        if child["type"] == "text"
          Array(child["marks"]).each { |mark| extend_or_add(marks, mark, start, start + Document::Body.utf16_length(piece)) }
        end
      end
      Block.new(index:, type: node["type"], pos:, text:, marks:)
    end

    def inline_text(node)
      case node["type"]
      when "text" then node["text"]
      when "hardBreak" then "\n"
      else ""
      end
    end

    def extend_or_add(marks, mark, start, finish)
      attrs = mark["attrs"] || {}
      previous = marks.reverse.find { |m| m.type == mark["type"] && m.end == start && m.attrs == attrs }
      if previous
        marks[marks.index(previous)] = previous.with(end: finish)
      else
        marks << Mark.new(type: mark["type"], attrs:, start:, end: finish)
      end
    end

    def node_size(node)
      case node["type"]
      when "text" then Document::Body.utf16_length(node["text"])
      when "hardBreak", "horizontalRule" then 1
      else
        inner = Array(node["content"]).sum { |child| node_size(child) }
        node["type"] == "doc" ? inner : inner + 2
      end
    end
end
