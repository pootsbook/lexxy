import { expect, test } from "@playwright/test"

// The seed imports one document: Tesseract page 42 (with the OCR miss
// "togther" and a Rom 8:28 citation) and an LLM-read page 43.

test("a correction survives save, is attributed, traced and printed", async ({ page, request }) => {
  await page.goto("/")
  await page.getByLabel("Your name").fill("ruth")
  await page.getByRole("button", { name: "Edit as" }).click()

  await page.getByRole("link", { name: "Commentary on Romans, page 42" }).click()
  const documentUrl = page.url()
  await page.getByRole("link", { name: "Edit" }).click()

  await page.locator(".ProseMirror").click()
  await page.evaluate(() => {
    const editor = document.querySelector("#editor").editor
    let target = null
    editor.state.doc.descendants((node, pos) => {
      if (target === null && node.isText && node.text.includes("ther for")) target = pos + node.text.indexOf("ther for")
    })
    editor.commands.setTextSelection(target)
  })
  await page.keyboard.type("e")
  await expect(page.locator(".ProseMirror")).toContainText("work together for good")

  await page.getByRole("button", { name: "Save" }).click()
  await expect(page.locator("#status")).toHaveText("Saved")

  // Reading page: corrected text, citation markup, no provenance data.
  await page.goto(documentUrl)
  await expect(page.locator(".reading")).toContainText("all things work together for good")
  await expect(page.locator(".reading cite[data-osis='Rom.8.28']")).toHaveText("Rom 8:28")
  expect(await page.locator(".reading [data-origin]").count()).toBe(0)
  await expect(page.locator(".summary")).toContainText("human")

  // The typed "e" is human and attributed to the session user, not the client.
  const id = documentUrl.split("/").pop()
  const offset = "And we know that all things work tog".length
  const human = await (await request.get(`/documents/${id}/provenance.json?block=0&offset=${offset}`)).json()
  expect(human).toMatchObject({ char: "e", origin: "human", by: "ruth", glyph: null })

  // The character after it still traces back to Tesseract's glyph for "togther".
  const ocr = await (await request.get(`/documents/${id}/provenance.json?block=0&offset=${offset + 1}`)).json()
  expect(ocr).toMatchObject({ char: "t", origin: "tesseract", glyph: { word: "togther", conf: 91, engine: "tesseract", page: 42 } })

  await page.getByRole("link", { name: "Corrections" }).click()
  await expect(page.locator(".corrections tbody tr").first()).toContainText("ruth")
  await expect(page.locator(".corrections tbody")).toContainText("insert e")

  // Citation search finds the document through the verse index.
  await page.getByLabel("Search by citation").fill("Rom.8")
  await page.getByRole("button", { name: "Find citations" }).click()
  await expect(page.locator(".citations li")).toHaveCount(2)

  const pdf = await request.get(`/documents/${id}.pdf`)
  expect(pdf.headers()["content-type"]).toContain("application/pdf")
  expect((await pdf.body()).subarray(0, 5).toString()).toBe("%PDF-")
})
