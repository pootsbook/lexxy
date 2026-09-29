import { createEditor } from "../src/editor.js"

// Mounts the provenance editor on the Rails edit page (#editor) and saves the
// body together with the correction events collected since the last save.
const element = document.querySelector("#editor")
const { body, updateUrl, provenanceUrl, human } = element.dataset
const status = document.querySelector("#status")
const origin = document.querySelector("#origin")

let pending = []
const editor = createEditor({ element, content: JSON.parse(body), human: JSON.parse(human), onEvent: event => pending.push(event) })
element.editor = editor

document.querySelector("#save").addEventListener("click", save)
editor.on("selectionUpdate", ({ editor }) => showOrigin(editor.state.selection.$from))

async function save() {
  const events = pending
  pending = []
  status.textContent = "Saving…"

  const response = await fetch(updateUrl, {
    method: "PATCH",
    headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": csrfToken() },
    body: JSON.stringify({ document: { body: editor.getJSON() }, events })
  })

  if (response.ok) {
    status.textContent = "Saved"
  } else {
    pending = events.concat(pending)
    const { errors } = await response.json().catch(() => ({ errors: [ response.statusText ] }))
    status.textContent = `Not saved: ${errors.join(", ")}`
  }
}

// Asks the server about the character after the caret. Block index and
// offset use the same rules as the stand-off index: textblocks in document
// order, offsets in UTF-16 units with a hard break counting as one.
async function showOrigin($pos) {
  if (!$pos.parent.isTextblock || $pos.parentOffset >= $pos.parent.content.size) return

  const url = new URL(provenanceUrl, location.href)
  url.searchParams.set("block", textblockIndex($pos))
  url.searchParams.set("offset", $pos.parentOffset)

  const response = await fetch(url, { headers: { "Accept": "application/json" } })
  origin.textContent = response.ok ? JSON.stringify(await response.json(), null, 2) : "Save first: the server hasn't indexed this text yet."
}

function textblockIndex($pos) {
  const start = $pos.before()
  let index = 0
  editor.state.doc.descendants((node, pos) => {
    if (pos >= start) return false
    if (node.isTextblock) {
      index++
      return false
    }
  })
  return index
}

function csrfToken() {
  return document.querySelector("meta[name=csrf-token]")?.content
}
