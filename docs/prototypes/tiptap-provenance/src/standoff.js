// Flattens a ProseMirror document into textblocks with stand-off mark ranges:
// the shape a backend indexes (citations table, provenance table) and the
// shape a canonical store could keep.
export function toStandoff(doc) {
  const blocks = []

  doc.descendants((node, pos) => {
    if (!node.isTextblock) return true

    const marks = []
    let text = ""
    node.forEach(child => {
      const piece = inlineText(child)
      if (child.isText) {
        child.marks.forEach(mark => extendOrAdd(marks, mark, text.length, text.length + piece.length))
      }
      text += piece
    })

    blocks.push({ type: node.type.name, pos, text, marks })
    return false
  })

  return blocks
}

// Offsets count what a reader sees: a hard break is a newline, other inline
// leaves count as nothing. The Rails side (Document::Body) uses the same rule.
function inlineText(node) {
  if (node.isText) return node.text
  if (node.type.name === "hardBreak") return "\n"
  return ""
}

function extendOrAdd(marks, mark, start, end) {
  const previous = marks.findLast(m => m.type === mark.type.name && m.end === start && sameAttrs(m.attrs, mark.attrs))
  if (previous) {
    previous.end = end
  } else {
    marks.push({ type: mark.type.name, attrs: { ...mark.attrs }, start, end })
  }
}

function sameAttrs(a, b) {
  return JSON.stringify(a) === JSON.stringify(b)
}

// Reading output: the same document with provenance removed.
export function withoutMarks(json, markName) {
  if (Array.isArray(json)) return json.map(item => withoutMarks(item, markName))
  if (json === null || typeof json !== "object") return json

  const copy = {}
  for (const [ key, value ] of Object.entries(json)) {
    if (key === "marks") {
      const kept = value.filter(mark => mark.type !== markName)
      if (kept.length > 0) copy.marks = kept
    } else {
      copy[key] = withoutMarks(value, markName)
    }
  }
  return copy
}
