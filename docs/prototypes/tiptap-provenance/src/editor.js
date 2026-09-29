import { Editor } from "@tiptap/core"
import StarterKit from "@tiptap/starter-kit"
import { Provenance, ProvenanceTracking } from "./provenance.js"
import { BibleRef } from "./bible_ref.js"

export function createEditor({ element, content, human, onEvent = () => {} }) {
  return new Editor({
    element,
    content,
    extensions: [
      StarterKit,
      Provenance,
      BibleRef,
      ProvenanceTracking.configure({ human, onEvent })
    ]
  })
}

export function ocr(text, run, origin = "tesseract") {
  return { type: "text", text, marks: [ { type: "provenance", attrs: { origin, run, by: null, session: null } } ] }
}
