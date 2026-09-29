import { expect, test } from "@playwright/test"

// The demo's first paragraph is one Tesseract run containing the OCR miss
// "togther", followed by a Rom 8:28 citation.

async function placeCaretBefore(page, needle) {
  // Real DOM focus first: Tiptap's focus command defers to the next frame, and
  // keystrokes sent before it lands go nowhere.
  await page.locator(".ProseMirror").focus()
  await page.evaluate(needle => {
    const { editor } = window
    let found = null
    editor.state.doc.descendants((node, pos) => {
      if (found === null && node.isText && node.text.includes(needle)) found = pos + node.text.indexOf(needle)
    })
    editor.commands.setTextSelection(found)
  }, needle)
}

async function runs(page, block = 0) {
  return page.evaluate(block => {
    const { text, marks } = window.standoff()[block]
    return marks.filter(m => m.type === "provenance").map(m => ({ text: text.slice(m.start, m.end), origin: m.attrs.origin }))
  }, block)
}

test.beforeEach(async ({ page }) => {
  await page.goto("/")
  await page.waitForFunction(() => window.editor)
})

test("keyboard typing mid-word marks only the typed character", async ({ page }) => {
  await placeCaretBefore(page, "ther for")
  await page.keyboard.type("e")

  await expect.poll(() => runs(page)).toEqual([
    { text: "And we know that all things work tog", origin: "tesseract" },
    { text: "e", origin: "human" },
    { text: "ther for good to them that love God (Rom 8:28).", origin: "tesseract" }
  ])
})

test("Backspace logs the deleted OCR character", async ({ page }) => {
  await placeCaretBefore(page, "ings work")
  await page.keyboard.press("Backspace")

  // Plain character deletion is native contenteditable behaviour; ProseMirror
  // reads it back from a MutationObserver, so the transaction lands a tick later.
  await expect.poll(() => page.evaluate(() => window.provenanceEvents.some(e => e.type === "delete"))).toBe(true)
  const deletion = await page.evaluate(() => window.provenanceEvents.find(e => e.type === "delete"))
  expect(deletion.pieces).toEqual([ { text: "h", provenance: { origin: "tesseract", run: "r_1", by: null, session: null } } ])
})

test("IME composition is recorded as human input", async ({ page }) => {
  await placeCaretBefore(page, "God")
  const cdp = await page.context().newCDPSession(page)
  await cdp.send("Input.imeSetComposition", { text: "ka", selectionStart: 2, selectionEnd: 2 })
  await cdp.send("Input.imeSetComposition", { text: "か", selectionStart: 1, selectionEnd: 1 })
  await cdp.send("Input.insertText", { text: "か" })

  await expect.poll(() => page.evaluate(() => window.editor.getText())).toContain("かGod")
  const human = (await runs(page)).filter(r => r.origin === "human")
  expect(human).toEqual([ { text: "か", origin: "human" } ])
})

test("undo after typing restores the original OCR run", async ({ page }) => {
  const before = await runs(page)
  await placeCaretBefore(page, "ther for")
  await page.keyboard.type("e")
  await expect.poll(() => page.evaluate(() => window.editor.getText())).toContain("together")
  await page.keyboard.press("ControlOrMeta+z")

  await expect.poll(() => runs(page)).toEqual(before)
})

test("clipboard paste of plain text is human, of editor HTML keeps provenance", async ({ page }) => {
  await placeCaretBefore(page, "For whom")

  await page.evaluate(() => {
    const paste = (type, data) => {
      const clipboardData = new DataTransfer()
      clipboardData.setData(type, data)
      window.editor.view.dom.dispatchEvent(new ClipboardEvent("paste", { clipboardData, bubbles: true, cancelable: true }))
    }
    paste("text/plain", "Amen. ")
    paste("text/html", `<span data-origin="tesseract" data-run="r_1">Moreover,</span>`)
  })

  expect(await runs(page, 1)).toEqual([
    { text: "Amen. ", origin: "human" },
    { text: "Moreover,", origin: "tesseract" },
    { text: "For whom he did foreknow, he also did predestinate", origin: "llm" }
  ])
})

test("reading HTML shows the citation but no provenance", async ({ page }) => {
  const reading = await page.locator("#reading").innerHTML()
  expect(reading).toContain(`<cite class="bible-ref" data-osis="Rom.8.28">Rom 8:28</cite>`)
  expect(reading).not.toContain("data-origin")
})
