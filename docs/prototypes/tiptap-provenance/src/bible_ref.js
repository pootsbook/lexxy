import { Mark, mergeAttributes } from "@tiptap/core"

export const BibleRef = Mark.create({
  name: "bibleRef",

  // Typing right after "Rom 8:28" shouldn't extend the citation.
  inclusive: false,

  addAttributes() {
    return {
      osis: { default: null, parseHTML: el => el.dataset.osis, renderHTML: a => ({ "data-osis": a.osis }) }
    }
  },

  parseHTML() {
    return [ { tag: "cite[data-osis]" } ]
  },

  renderHTML({ HTMLAttributes }) {
    return [ "cite", mergeAttributes({ class: "bible-ref" }, HTMLAttributes), 0 ]
  }
})
