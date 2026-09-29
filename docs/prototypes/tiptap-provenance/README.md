# Tiptap provenance prototype

A spike for the riskiest part of an OCR-correction editor: knowing, for every character, whether it came from Tesseract, an LLM, or a human, and keeping that true through real editing. Bible citations ride along as a second mark to show how stand-off export feeds a search index.

This lives in the Lexxy fork only as a research artifact; it doesn't use or affect Lexxy.

## Run it

```sh
npm install
npm test               # Vitest + jsdom: transaction-level behaviour (16 tests)
npm run test:browser   # Playwright + Chromium: real keyboard, IME, clipboard (6 tests)
npm run demo           # http://localhost:5173 — colour-coded editor, event log, reading HTML, stand-off JSON
```

Playwright uses `/opt/pw-browsers/chromium` by default; set `CHROMIUM_PATH` to point elsewhere, or delete `launchOptions` in `playwright.config.js` to use Playwright's own browsers.

## How it works

`src/provenance.js`:

- **`Provenance` mark**: `{ origin, run, by, session }`. It renders as `<span data-origin …>` so copy-paste between editors carries provenance. The mark holds only what identifies a run. Per-character confidence, bounding boxes and alternatives belong in a side table keyed by `run` and offset.
- **`ProvenanceTracking` extension**: one `appendTransaction` plugin. For every transaction that changed the document:
  - Each step's map gives exact inserted and deleted ranges, with no text diffing. Inserted ranges are mapped forward to the final state and marked `human` with the configured `by` and `session`. Consecutive typing merges into one run because the attributes are equal.
  - Deleted text is reported through `onEvent` along with its original provenance, so a correction log can say "human replaced tesseract `togther`".
  - **Undo/redo** (`isHistoryTransaction`) is never re-marked. The appended mark step joins the same undo event, so undo restores the OCR text and marks exactly.
  - **Identical re-commits** (an IME or Android keyboard replacing a word with itself) keep the original provenance.
  - **Paste and drop**: prosemirror-view applies the cursor's marks to pasted content, so the plugin records the clipboard slice's own provenance in `transformPasted` and re-applies it. Pasted plain text counts as human; HTML copied from the editor keeps its marks.
  - **Clear formatting** (`RemoveMarkStep` on provenance) is undone: provenance isn't formatting.
- **Machine edits**: anything tagged `setMeta(provenanceKey, MACHINE_EDIT)` is left alone. `insertMachineContent(content, pos)` uses this for an LLM or OCR pass, and keeps it out of undo history.

`src/standoff.js` flattens the document to textblocks with `{ type, attrs, start, end }` mark ranges. These are the rows for a citations table and a provenance table, and the shape of a canonical store. `withoutMarks(json, "provenance")` plus `generateHTML` produces the reading view.

## What the tests cover

| Scenario | Where |
|----------|-------|
| Typing mid-word splits the OCR run; only the typed character is human | unit + browser |
| Consecutive typing merges into one human run | unit |
| Replacement logs deleted characters with their provenance | unit + browser (Backspace) |
| Identical re-commit keeps provenance | unit |
| Split paragraph, heading, bullet list: no human text created | unit |
| Undo restores the exact original document; redo re-applies | unit + browser (Ctrl/Cmd+Z) |
| History events flagged `fromHistory` | unit |
| Plain-text paste is human; editor-HTML paste keeps provenance, including multi-paragraph | unit + browser (real `ClipboardEvent`) |
| Bold and clear formatting leave provenance alone | unit |
| Machine insert has its own provenance and no undo step | unit |
| IME composition (Chromium CDP) is human | browser |
| Stand-off export; reading HTML has citations but no provenance | unit + browser |

## Known gaps

- **Drag-to-move within the editor** takes the same `transformPasted` path as paste, but has no test yet.
- **Spellcheck and autocorrect replacements** (`insertReplacementText`) and Android IME recomposition aren't simulated. The identical-replacement rule exists for them, but only a real device will tell.
- **Deletion events come from `appendTransaction`**, which runs once per transaction batch. For a durable correction log, persist events server-side on save rather than trusting a client stream.
- **Collaborative editing (Yjs)** would need provenance decided per client update. The same step-based approach applies, but it isn't done here.
- **`#mappingAfter` rebuilds a mapping per step**, which is quadratic in steps per batch. That's fine for typing and paste; profile before running bulk transforms through it.
