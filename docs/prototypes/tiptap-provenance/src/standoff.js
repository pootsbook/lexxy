// Flattens a ProseMirror document into textblocks with stand-off mark ranges:
// the shape a backend indexes (citations table, provenance table) and the
// shape a canonical store could keep.
export function toStandoff(doc) {
  const blocks = []

  doc.descendants((node, pos) => {
    if (!node.isTextblock) return true

    const marks = []
    let offset = 0
    node.forEach(child => {
      if (child.isText) {
        child.marks.forEach(mark => extendOrAdd(marks, mark, offset, offset + child.text.length))
      }
      offset += child.isText ? child.text.length : 0
    })

    blocks.push({ type: node.type.name, pos, text: node.textContent, marks })
    return false
  })

  return blocks
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
