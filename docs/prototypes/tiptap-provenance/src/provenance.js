import { Extension, Mark, mergeAttributes } from "@tiptap/core"
import { Plugin, PluginKey } from "@tiptap/pm/state"
import { isHistoryTransaction } from "@tiptap/pm/history"
import { Mapping, RemoveMarkStep, ReplaceAroundStep, ReplaceStep } from "@tiptap/pm/transform"

export const provenanceKey = new PluginKey("provenance")

// Transactions carrying this meta are not treated as human edits: loading OCR
// output, applying an LLM pass, or the plugin's own appended transactions.
export const MACHINE_EDIT = "machine-edit"

const MOVE_EVENTS = [ "paste", "drop" ]

export const Provenance = Mark.create({
  name: "provenance",

  // Typed text inherits the mark it's typed into. The plugin below overwrites
  // that inherited mark, so inclusiveness only decides what gets overwritten.
  inclusive: true,

  addAttributes() {
    return {
      origin: { default: null, parseHTML: el => el.dataset.origin, renderHTML: a => ({ "data-origin": a.origin }) },
      run: { default: null, parseHTML: el => el.dataset.run ?? null, renderHTML: a => (a.run ? { "data-run": a.run } : {}) },
      by: { default: null, parseHTML: el => el.dataset.by ?? null, renderHTML: a => (a.by ? { "data-by": a.by } : {}) },
      session: { default: null, parseHTML: el => el.dataset.session ?? null, renderHTML: a => (a.session ? { "data-session": a.session } : {}) }
    }
  },

  parseHTML() {
    return [ { tag: "span[data-origin]" } ]
  },

  renderHTML({ HTMLAttributes }) {
    return [ "span", mergeAttributes({ class: "provenance" }, HTMLAttributes), 0 ]
  }
})

export const ProvenanceTracking = Extension.create({
  name: "provenanceTracking",

  addOptions() {
    return {
      // Attributes stamped on every human-inserted character. Keep them stable
      // for a whole editing session so consecutive typing merges into one run;
      // per-keystroke detail belongs in the event log, not in the mark.
      human: { origin: "human", by: null, session: null },
      onEvent: () => {}
    }
  },

  addCommands() {
    return {
      insertMachineContent: (content, position) => ({ chain }) => {
        return chain().setMeta(provenanceKey, MACHINE_EDIT).setMeta("addToHistory", false).insertContentAt(position, content).run()
      }
    }
  },

  addProseMirrorPlugins() {
    const markType = this.editor.schema.marks.provenance
    const humanMark = markType.create(this.options.human)
    const onEvent = this.options.onEvent

    // prosemirror-view gives pasted content the marks at the cursor (plain
    // text is parsed with them; a single pasted node has its marks replaced),
    // so the doc can't tell us what the clipboard carried. We note the slice's
    // own provenance here and re-apply it once the paste lands.
    const clipboard = { pieces: null }

    return [
      new Plugin({
        key: provenanceKey,
        props: {
          transformPasted(slice, _view, plainText) {
            clipboard.pieces = slicePieces(slice, plainText ? null : markType)
            return slice
          }
        },
        appendTransaction(transactions, _oldState, newState) {
          const tracker = new ProvenanceTracker(markType, humanMark, transactions, newState, clipboard)
          tracker.collect()
          tracker.events.forEach(onEvent)
          if (transactions.some(tr => MOVE_EVENTS.includes(tr.getMeta("uiEvent")))) clipboard.pieces = null
          return tracker.buildTransaction()
        }
      })
    ]
  }
})

// Plain text has no provenance of its own: pass markType null.
function slicePieces(slice, markType) {
  const pieces = []
  slice.content.descendants(node => {
    if (node.isText) pieces.push({ text: node.text, mark: markType?.isInSet(node.marks) ?? null })
  })
  return pieces
}

class ProvenanceTracker {
  #markType
  #humanMark
  #transactions
  #newState
  #clipboard
  #insertions = []
  #restorations = []

  events = []

  constructor(markType, humanMark, transactions, newState, clipboard) {
    this.#markType = markType
    this.#humanMark = humanMark
    this.#transactions = transactions
    this.#newState = newState
    this.#clipboard = clipboard
  }

  collect() {
    this.#transactions.forEach((tr, index) => {
      if (tr.docChanged && tr.getMeta(provenanceKey) !== MACHINE_EDIT) {
        this.#collectTransaction(tr, index)
      }
    })
  }

  buildTransaction() {
    if (this.#insertions.length === 0 && this.#restorations.length === 0) return null

    const tr = this.#newState.tr
    this.#insertions.forEach(({ from, to }) => tr.addMark(from, to, this.#humanMark))
    this.#restorations.forEach(({ from, to, mark }) => tr.addMark(from, to, mark))

    if (!tr.docChanged) return null

    return tr.setMeta(provenanceKey, MACHINE_EDIT)
  }

  #collectTransaction(tr, index) {
    const fromHistory = isHistoryTransaction(tr)
    const uiEvent = tr.getMeta("uiEvent") ?? null
    const pasted = MOVE_EVENTS.includes(uiEvent) ? this.#clipboard.pieces : null

    tr.steps.forEach((step, stepIndex) => {
      const docBefore = tr.docs[stepIndex]
      const docAfter = stepIndex + 1 < tr.docs.length ? tr.docs[stepIndex + 1] : tr.doc
      const toNewState = this.#mappingAfter(index, stepIndex)

      if (step instanceof ReplaceStep || step instanceof ReplaceAroundStep) {
        step.getMap().forEach((oldStart, oldEnd, newStart, newEnd) => {
          const deleted = this.#textPieces(docBefore, oldStart, oldEnd)
          // Text only: a split paragraph inserts block boundaries, not characters.
          const insertedText = this.#textPieces(docAfter, newStart, newEnd).map(piece => piece.text).join("")

          if (deleted.length > 0) {
            this.events.push({ type: "delete", pieces: deleted.map(({ text, provenance }) => ({ text, provenance })), uiEvent, fromHistory })
          }

          if (insertedText.length > 0) {
            this.events.push({ type: "insert", text: insertedText, uiEvent, fromHistory })
          }

          if (!fromHistory && insertedText.length > 0) {
            const from = toNewState.map(newStart, 1)
            const to = toNewState.map(newEnd, -1)
            if (from < to) {
              if (this.#isIdenticalReplacement(deleted, insertedText)) {
                this.#reapply(deleted, from, to)
              } else if (pasted && this.#sameText(pasted, insertedText)) {
                this.#reapply(pasted, from, to)
              } else {
                this.#insertions.push({ from, to })
              }
            }
          }
        })
      } else if (step instanceof RemoveMarkStep && step.mark.type === this.#markType && !fromHistory) {
        this.#restoreRemovedMarks(docBefore, step.from, step.to, toNewState)
      }
    })
  }

  // Maps a position in the document right after the given step into newState.
  // Built from step maps because Mapping#slice shares its maps array, which
  // appendMapping would then copy in full.
  #mappingAfter(transactionIndex, stepIndex) {
    const mapping = new Mapping()
    this.#transactions[transactionIndex].steps.slice(stepIndex + 1).forEach(step => mapping.appendMap(step.getMap()))
    this.#transactions.slice(transactionIndex + 1).forEach(tr => {
      tr.steps.forEach(step => mapping.appendMap(step.getMap()))
    })
    return mapping
  }

  #textPieces(doc, from, to) {
    const pieces = []
    if (to <= from) return pieces

    doc.nodesBetween(from, to, (node, pos) => {
      if (node.isText) {
        const start = Math.max(from, pos)
        const end = Math.min(to, pos + node.nodeSize)
        const mark = this.#markType.isInSet(node.marks)
        pieces.push({ at: start, text: node.text.slice(start - pos, end - pos), provenance: mark ? mark.attrs : null, mark })
      }
    })
    return pieces
  }

  // Android keyboards and some IMEs re-commit a word they didn't change. That
  // isn't a correction, so the original provenance is kept.
  #isIdenticalReplacement(deleted, insertedText) {
    return deleted.length > 0 && this.#sameText(deleted, insertedText)
  }

  #sameText(pieces, text) {
    return pieces.map(piece => piece.text).join("") === text
  }

  // Lays pieces back over the inserted text, character for character: their
  // own provenance where they had one, human where they didn't. Walks text
  // nodes because a multi-paragraph insertion isn't contiguous.
  #reapply(pieces, from, to) {
    const queue = pieces.map(({ text, mark }) => ({ remaining: text.length, mark: mark ?? this.#humanMark }))

    this.#newState.doc.nodesBetween(from, to, (node, pos) => {
      if (!node.isText) return

      let position = Math.max(from, pos)
      const end = Math.min(to, pos + node.nodeSize)
      while (position < end && queue.length > 0) {
        const piece = queue[0]
        const length = Math.min(piece.remaining, end - position)
        this.#restorations.push({ from: position, to: position + length, mark: piece.mark })
        position += length
        piece.remaining -= length
        if (piece.remaining === 0) queue.shift()
      }
    })
  }

  // Commands like "clear formatting" strip every mark. Provenance isn't
  // formatting, so it's put back unless the removal was a MACHINE_EDIT.
  #restoreRemovedMarks(docBefore, from, to, toNewState) {
    this.#textPieces(docBefore, from, to).forEach(({ at, text, mark }) => {
      if (mark) {
        const mappedFrom = toNewState.map(at, 1)
        const mappedTo = toNewState.map(at + text.length, -1)
        if (mappedFrom < mappedTo) this.#restorations.push({ from: mappedFrom, to: mappedTo, mark })
      }
    })
  }
}
