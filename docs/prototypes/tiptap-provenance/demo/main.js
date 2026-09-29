import { generateHTML } from "@tiptap/html"
import StarterKit from "@tiptap/starter-kit"
import { createEditor, ocr } from "../src/editor.js"
import { Provenance } from "../src/provenance.js"
import { BibleRef } from "../src/bible_ref.js"
import { toStandoff, withoutMarks } from "../src/standoff.js"

const content = {
  type: "doc",
  content: [
    { type: "paragraph", content: [ ocr("And we know that all things work togther for good to them that love God (", "r_1"),
      { type: "text", text: "Rom 8:28", marks: [ { type: "bibleRef", attrs: { osis: "Rom.8.28" } }, { type: "provenance", attrs: { origin: "tesseract", run: "r_1", by: null, session: null } } ] },
      ocr(").", "r_1") ] },
    { type: "paragraph", content: [ ocr("For whom he did foreknow, he also did predestinate", "r_2", "llm") ] }
  ]
}

const events = []
const editor = createEditor({
  element: document.querySelector("#editor"),
  content,
  human: { origin: "human", by: "demo-user", session: `s_${Date.now()}` },
  onEvent: event => events.push(event)
})

function render() {
  const json = editor.getJSON()
  document.querySelector("#reading").innerHTML = generateHTML(withoutMarks(json, "provenance"), [ StarterKit, Provenance, BibleRef ])
  document.querySelector("#events").textContent = events.slice(-12).map(e => JSON.stringify(e)).join("\n")
  document.querySelector("#standoff").textContent = JSON.stringify(toStandoff(editor.state.doc), null, 2)
}

editor.on("update", render)
render()

window.editor = editor
window.provenanceEvents = events
window.standoff = () => toStandoff(editor.state.doc)
