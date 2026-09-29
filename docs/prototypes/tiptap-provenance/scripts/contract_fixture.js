// Writes the JS side of the stand-off contract for the Rails prototype:
// documents plus what toStandoff makes of them. Document::Body must produce
// identical blocks (see provenance-rails/test/models/document/body_test.rb).
// Run: node scripts/contract_fixture.js
import { writeFileSync } from "node:fs"
import { getSchema } from "@tiptap/core"
import { Node } from "@tiptap/pm/model"
import StarterKit from "@tiptap/starter-kit"
import { Provenance } from "../src/provenance.js"
import { BibleRef } from "../src/bible_ref.js"
import { toStandoff } from "../src/standoff.js"

const schema = getSchema([ StarterKit, Provenance, BibleRef ])
const ocr = (text, run, extra = []) => ({ type: "text", text, marks: [ ...extra, { type: "provenance", attrs: { origin: "tesseract", run, by: null, session: null } } ] })
const human = text => ({ type: "text", text, marks: [ { type: "provenance", attrs: { origin: "human", run: null, by: "ruth", session: "s1" } } ] })

const documents = {
  corrected_paragraph: { type: "doc", content: [
    { type: "paragraph", content: [ ocr("work tog", "r1"), human("e"), ocr("ther (", "r1"), ocr("Rom 8:28", "r1", [ { type: "bibleRef", attrs: { osis: "Rom.8.28" } } ]), ocr(")", "r1") ] }
  ] },
  nested_structure: { type: "doc", content: [
    { type: "heading", attrs: { level: 2 }, content: [ ocr("Chapter", "r2") ] },
    { type: "bulletList", content: [
      { type: "listItem", content: [ { type: "paragraph", content: [ ocr("first", "r2") ] } ] },
      { type: "listItem", content: [ { type: "paragraph", content: [ ocr("second", "r2"), { type: "hardBreak" }, human("line") ] } ] }
    ] },
    { type: "blockquote", content: [ { type: "paragraph", content: [ { type: "text", text: "quoted", marks: [ { type: "bold" } ] } ] } ] },
    { type: "horizontalRule" },
    { type: "paragraph" }
  ] },
  astral_characters: { type: "doc", content: [
    { type: "paragraph", content: [ ocr("𝔊od ", "r3"), human("🙏"), ocr(" amen", "r3") ] }
  ] }
}

const contract = Object.fromEntries(Object.entries(documents).map(([ name, json ]) => {
  const doc = Node.fromJSON(schema, json)
  return [ name, { body: doc.toJSON(), standoff: toStandoff(doc) } ]
}))

const target = new URL("../../provenance-rails/test/fixtures/files/standoff_contract.json", import.meta.url)
writeFileSync(target, JSON.stringify(contract, null, 2) + "\n")
console.log(`Wrote ${Object.keys(contract).length} documents to ${target.pathname}`)
