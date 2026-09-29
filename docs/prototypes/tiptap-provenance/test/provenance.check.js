import { afterEach, beforeEach, describe, expect, test } from "vitest"
import { TextSelection } from "@tiptap/pm/state"
import { generateHTML } from "@tiptap/html"
import StarterKit from "@tiptap/starter-kit"
import { createEditor, ocr } from "../src/editor.js"
import { Provenance, provenanceKey, MACHINE_EDIT } from "../src/provenance.js"
import { BibleRef } from "../src/bible_ref.js"
import { toStandoff, withoutMarks } from "../src/standoff.js"

// jsdom has no ClipboardEvent; prosemirror-view's pasteHTML/pasteText only
// needs one to exist. Real clipboard paste is covered in the browser tests.
globalThis.ClipboardEvent ??= class ClipboardEvent extends Event {
  clipboardData = null
}

const HUMAN = { origin: "human", by: "user_7", session: "s_1" }

let editor, events

function page(...paragraphs) {
  return { type: "doc", content: paragraphs.map(content => ({ type: "paragraph", content })) }
}

// "For we know that all things work together" — OCR'd by Tesseract in one run,
// with "togther" as a typical OCR miss we will correct.
const ORIGINAL = page([ ocr("For we know that all things work togther", "r_1") ])

beforeEach(() => {
  events = []
  editor = createEditor({ element: document.createElement("div"), content: ORIGINAL, human: HUMAN, onEvent: e => events.push(e) })
})

afterEach(() => editor.destroy())

function runs(blockIndex = 0) {
  return toStandoff(editor.state.doc)[blockIndex].marks
    .filter(m => m.type === "provenance")
    .map(m => ({ text: toStandoff(editor.state.doc)[blockIndex].text.slice(m.start, m.end), origin: m.attrs.origin, run: m.attrs.run }))
}

// Mirrors what prosemirror-view does for a keystroke: tr.insertText at the
// cursor, inheriting the marks there.
function type(text, at) {
  const { state, view } = editor
  view.dispatch(state.tr.insertText(text, at))
}

function positionOf(needle) {
  let found = null
  editor.state.doc.descendants((node, pos) => {
    if (found === null && node.isText) {
      const index = node.text.indexOf(needle)
      if (index >= 0) found = pos + index
    }
  })
  return found
}

describe("human edits", () => {
  test("typing mid-word splits the OCR run and marks only the typed character", () => {
    type("e", positionOf("ther"))

    expect(editor.getText()).toBe("For we know that all things work together")
    expect(runs()).toEqual([
      { text: "For we know that all things work tog", origin: "tesseract", run: "r_1" },
      { text: "e", origin: "human", run: null },
      { text: "ther", origin: "tesseract", run: "r_1" }
    ])
  })

  test("consecutive typing merges into a single human run", () => {
    const at = editor.state.doc.content.size - 1
    type(" for", at)
    type(" good", at + 4)

    expect(runs().at(-1)).toEqual({ text: " for good", origin: "human", run: null })
  })

  test("replacing characters logs what was deleted with its provenance", () => {
    const from = positionOf("togther")
    editor.view.dispatch(editor.state.tr.insertText("together", from, from + "togther".length))

    const deletion = events.find(e => e.type === "delete")
    expect(deletion.pieces).toEqual([ { text: "togther", provenance: { origin: "tesseract", run: "r_1", by: null, session: null } } ])
    expect(runs().at(-1)).toEqual({ text: "together", origin: "human", run: null })
  })

  test("re-committing identical text keeps the original provenance", () => {
    const from = positionOf("togther")
    editor.view.dispatch(editor.state.tr.insertText("togther", from, from + "togther".length))

    expect(runs()).toEqual([ { text: "For we know that all things work togther", origin: "tesseract", run: "r_1" } ])
  })

  test("turning a paragraph into a heading or list keeps provenance", () => {
    editor.commands.setHeading({ level: 2 })
    editor.commands.toggleBulletList()

    expect(runs()).toEqual([ { text: "For we know that all things work togther", origin: "tesseract", run: "r_1" } ])
    expect(events.filter(e => e.type === "insert")).toEqual([])
  })

  test("splitting a paragraph doesn't create human text", () => {
    editor.commands.setTextSelection(positionOf("all"))
    editor.commands.splitBlock()

    expect(runs(0)).toEqual([ { text: "For we know that ", origin: "tesseract", run: "r_1" } ])
    expect(runs(1)).toEqual([ { text: "all things work togther", origin: "tesseract", run: "r_1" } ])
  })
})

describe("history", () => {
  test("undo restores the exact OCR document and redo re-applies the correction", () => {
    type("e", positionOf("ther"))
    const corrected = editor.getJSON()

    editor.commands.undo()
    expect(editor.getJSON()).toEqual(ORIGINAL)

    editor.commands.redo()
    expect(editor.getJSON()).toEqual(corrected)
  })

  test("undo/redo events are reported as history, not new corrections", () => {
    type("e", positionOf("ther"))
    events.length = 0
    editor.commands.undo()

    expect(events.every(e => e.fromHistory)).toBe(true)
  })
})

describe("paste and formatting", () => {
  test("text pasted from outside is human", () => {
    const at = editor.state.doc.content.size - 1
    editor.view.dispatch(editor.state.tr.setSelection(TextSelection.create(editor.state.doc, at)))
    editor.view.pasteText(" for good")

    expect(runs().at(-1)).toMatchObject({ text: " for good", origin: "human" })
  })

  test("text copied from the editor keeps its provenance", () => {
    const at = editor.state.doc.content.size - 1
    editor.view.dispatch(editor.state.tr.setSelection(TextSelection.create(editor.state.doc, at)))
    editor.view.pasteHTML(`<p>, <span data-origin="llm" data-run="r_9">for good</span></p>`)

    expect(runs().slice(-2)).toEqual([
      { text: ", ", origin: "human", run: null },
      { text: "for good", origin: "llm", run: "r_9" }
    ])
  })

  test("a multi-paragraph paste keeps each piece's provenance", () => {
    const at = editor.state.doc.content.size - 1
    editor.view.dispatch(editor.state.tr.setSelection(TextSelection.create(editor.state.doc, at)))
    editor.view.pasteHTML(`<p>,</p><p><span data-origin="llm" data-run="r_9">for good</span> to them</p>`)

    expect(runs(0).at(-1)).toEqual({ text: ",", origin: "human", run: null })
    expect(runs(1)).toEqual([
      { text: "for good", origin: "llm", run: "r_9" },
      { text: " to them", origin: "human", run: null }
    ])
  })

  test("bold and clear-formatting leave provenance alone", () => {
    editor.chain().setTextSelection({ from: 1, to: 4 }).toggleBold().run()
    editor.chain().selectAll().unsetAllMarks().run()

    expect(runs()).toEqual([ { text: "For we know that all things work togther", origin: "tesseract", run: "r_1" } ])
  })
})

describe("machine edits", () => {
  test("an LLM pass inserts content with its own provenance and no undo step", () => {
    const at = editor.state.doc.content.size - 1
    editor.commands.insertMachineContent(ocr(" for good", "r_2", "llm"), at)

    expect(runs().at(-1)).toEqual({ text: " for good", origin: "llm", run: "r_2" })
    expect(editor.can().undo()).toBe(false)
  })

  test("a MACHINE_EDIT transaction can remove provenance deliberately", () => {
    editor.view.dispatch(editor.state.tr.removeMark(0, editor.state.doc.content.size).setMeta(provenanceKey, MACHINE_EDIT))
    expect(runs()).toEqual([])
  })
})

describe("outputs", () => {
  test("stand-off export gives rows for the citation and provenance indexes", () => {
    editor.commands.setContent(page([
      ocr("As ", "r_1"),
      { type: "text", text: "Rom 8:28", marks: [ { type: "bibleRef", attrs: { osis: "Rom.8.28" } }, { type: "provenance", attrs: { origin: "tesseract", run: "r_1", by: null, session: null } } ] },
      ocr(" says", "r_1")
    ]))

    const [ block ] = toStandoff(editor.state.doc)
    expect(block.marks).toContainEqual({ type: "bibleRef", attrs: { osis: "Rom.8.28" }, start: 3, end: 11 })
    expect(block.marks.filter(m => m.type === "provenance")).toHaveLength(1)
  })

  test("reading HTML carries citations but no provenance", () => {
    type("e", positionOf("ther"))
    const extensions = [ StarterKit, Provenance, BibleRef ]

    const editing = generateHTML(editor.getJSON(), extensions)
    const reading = generateHTML(withoutMarks(editor.getJSON(), "provenance"), extensions)

    expect(editing).toContain(`data-origin="human"`)
    expect(reading).toBe("<p>For we know that all things work together</p>")
  })
})
