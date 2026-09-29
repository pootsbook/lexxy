ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)

    # The sample is real engine output shape: Tesseract page 42 with the OCR
    # miss "togther" and three citations, and an LLM-read page 43.
    def import_sample
      sample = ::JSON.parse(file_fixture("romans_pages.json").read)
      OcrImport.new(title: sample["title"], pages: sample["pages"]).tap(&:save!).document
    end

    def paragraph_text(document, block_index = 0)
      document.content.blocks[block_index].text
    end

    # Mimics an editor save: replaces `from`..`to` of a textblock's first
    # matching text node with human text, splitting the node's marks.
    def correct(document, find:, replace_with:, user: "ruth")
      body = document.body.deep_dup
      paragraph = body["content"].find { |node| node["content"]&.any? { |child| child["text"]&.include?(find) } }
      index = paragraph["content"].index { |child| child["text"]&.include?(find) }
      node = paragraph["content"][index]
      before, after = node["text"].split(find, 2)
      human = { "type" => "text", "text" => replace_with, "marks" => [ { "type" => "provenance", "attrs" => { "origin" => "human", "run" => nil, "by" => user, "session" => "s1" } } ] }
      paragraph["content"][index, 1] = [ node.merge("text" => before), human, node.merge("text" => after) ].reject { |child| child["text"].empty? }

      document.revise(body:, events: [ { type: "delete", pieces: [ { text: find, provenance: node["marks"].last["attrs"] } ] }, { type: "insert", text: replace_with } ], user_name: user)
    end
  end
end
