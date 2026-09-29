# Lexxy architecture deep dive

A map of how Lexxy 1.0 works, from the Rails form helper down to Lexical's reconciler and back to the rendered page. This overview is the entry point; the detailed notes (with `file:line` anchors) live alongside it:

| File | Covers |
|------|--------|
| [js_core.md](js_core.md) | `<lexxy-editor>` lifecycle, configuration, sanitization, the `Contents`/`Selection`/`Clipboard`/`CommandDispatcher` controllers, paste & markdown, uploads, prompts core |
| [extensions_ui.md](extensions_ui.md) | Lexical's Extension API, every built-in Lexxy extension, every custom node, toolbar/dropdowns/table tools/prompt UI, CSS, build, test suites |
| [actiontext.md](actiontext.md) | Action Text internals on Rails main (8.2.0.alpha), the `ActionText::Editor` adapter, Lexxy's Ruby side file by file, end-to-end data flow |
| [website_and_release.md](website_and_release.md) | Everything in `home/` (lexxy.dev source): install, config, events, prompts, attachments, extensions, hotkeys, a11y, CSP; the 1.0 release post claims; doc discrepancies |

Versions studied: Lexxy 1.0.0 (`ea8ab63`), Lexical 0.44.0, Rails `main` (Action Text 8.2.0.alpha).

> Source caveat: lexxy.dev and dev.37signals.com were unreachable from the research environment, so the site was studied from its source in `home/`, and claims attributed to the 1.0 release post are paraphrased from search summaries rather than quoted.

---

## 1. The one-paragraph version

Lexxy is a **form-associated custom element** (`<lexxy-editor>`) that owns a **Lexical** editor built with `buildEditorFromExtensions`. Its value is **Action Text's canonical HTML** — `<action-text-attachment sgid=… content-type=…>` and all — so, unlike Trix, it needs no conversion layer: on Rails main the `ActionText::Editor::LexxyEditor` adapter's `as_canonical`/`as_editable` are identities. Every Lexical update re-exports HTML with `$generateHtmlFromNodes`, runs it through a per-editor DOMPurify allowlist, and hands it to `ElementInternals.setFormValue`, so the form submits `post[body]` like any input. Optional behavior (tables, code highlighting, color highlights, attachments, history rewriting, Trix-content import…) is packaged as **Lexxy extensions** that wrap Lexical extensions, and the same mechanism is exposed to host apps.

## 2. Why it exists (release post + site)

- Trix (2015, Rails' editor since Action Text in Rails 6) has a flat block model — a block can't contain a block — which made tables and similar features impractical; raw `contenteditable` handling was a growing maintenance cost.
- Lexical provides a real node tree, a reconciler, command/transform/extension APIs, and a large production track record.
- Headline features: tables, markdown shortcuts and markdown paste, Prism-highlighted code blocks, image galleries, prompts (mentions, emoji, anything with an SGID), color/background highlights, extensions, accessibility work, sanitization. Perf claim: ~4 ms per keystroke on a 10k-word doc vs ~38 ms for Trix.
- Rails 8.2 makes it a one-liner: `config.action_text.editor = :lexxy` (Lexxy's engine sets this automatically).

## 3. Layered architecture

```
 Rails view ── form.rich_text_area :body
    │  ActionText::TagHelper#rich_textarea_tag → value = content.to_editor_html
    │  RichText.editor.editor_tag  (LexxyEditor::Tag, Rails main)
    │  or Lexxy::TagHelper monkey-patch (Rails 8.0/8.1)
    ▼
 <lexxy-editor name="post[body]" value="…canonical HTML…" data-direct-upload-url data-blob-url-template>
    <lexxy-prompt trigger="@" src="/people">…</lexxy-prompt>          (optional children)
 ─────────────────────────── browser ─────────────────────────────────────────
 LexicalEditorElement (src/elements/editor.js)       ← custom element, formAssociated
   ├─ Configuration      (src/editor/configuration.js)  default preset ▸ named preset ▸ attributes
   ├─ Extensions         (src/editor/extensions.js)     12 built-ins + global.extensions
   ├─ Lexical editor     buildEditorFromExtensions({name:"lexxy/core", nodes, theme, html.export,
   │                        $initialEditorState}, ...extension.lexicalExtension)
   ├─ Contents           insertion strategies, block formats, links, uploads
   ├─ Selection          format queries, decorator/attachment navigation
   ├─ Clipboard          paste: code/URL/markdown/HTML routing
   ├─ CommandDispatcher  string commands ("bold", "insertTable", …) used by toolbar
   ├─ EditorSanitizer    DOMPurify, allowlist = importable tags + extension allowedElements
   ├─ Adapter            BrowserAdapter (DOM events) | NativeAdapter (iOS/Android bridges)
   └─ UI children        <lexxy-toolbar>, <lexxy-table-tools>, <lexxy-attachment-toolbar>,
                         <lexxy-code-language-picker>, <lexxy-live-region>, <lexxy-prompt>
 ─────────────────────────── submit ──────────────────────────────────────────
 post[body] = sanitize($generateHtmlFromNodes())
    ▼
 ActionText::Content.new(html) → as_canonical (identity) → minify attachments → store
 render: attachment partials (to_attachable_partial_path) → rails-html-sanitizer allowlist
 re-edit: to_editor_html → content attribute rendered via to_editor_content_attachment_partial_path
```

## 4. The `<lexxy-editor>` element

Source: `src/elements/editor.js`.

**Boot order.** `src/index.js` defines the custom elements in a `setTimeout(…, 0)` so `Lexxy.configure()` can run synchronously after import. Registration order matters: `lexxy-toolbar` before `lexxy-editor`, `lexxy-prompt` after it (`src/elements/index.js`).

**`connectedCallback`:**
1. `Configuration` and `Extensions` are built (extensions filtered by `enabled`).
2. `#createEditor` calls `buildEditorFromExtensions` with a root `lexxy/core` extension: the theme (`src/config/theme.js`), core nodes (`CustomActionTextAttachmentNode` always; Quote/Heading/List/Code/Link/AutoLink/HorizontalDivider only in rich-text mode), `html.export` overrides for `TextNode` and `CodeHighlightNode`, and `$initialEditorState`, which registers the sanitizer and loads the initial value. Lexical's `InitialStateExtension` applies that after all extensions register, tagged history-merge so it isn't undoable.
3. The controllers, live region, adapter, upload request registry and `CommandDispatcher` are created.
4. `#initialize` registers rich text + lists + markdown shortcuts (or plain text), Enter handling, focus/blur, history state, the file-accept filter, toolbar, Turbo cache reset and ARIA mirroring, then seeds the form value.
5. Next animation frame: `#mountRoot` calls `setRootElement` while temporarily non-editable, which skips Lexical's DOM-selection sync so mounting doesn't steal focus. Then autofocus and `lexxy:initialize`.

**Initial value:** `valueBeforeDisconnect`, else the `value` attribute, else `<p><br></p>`. The HTML is parsed, imported via `$generateNodesFromDOM`, filtered for disallowed attachment types, stripped of whitespace-only and stray line-break nodes, and bare text is wrapped in paragraphs.

**Value out:** `get value` is a cached `sanitizer.sanitize($generateHtmlFromNodes(editor, null))`. An update listener clears caches, calls `internals.setFormValue`, fires `lexxy:change` only when the HTML actually changed, toggles `lexxy-editor--empty`, refreshes validity and emits toolbar state. `set value(html)` runs a discrete update, skipping the DOM-selection sync unless the editor is focused.

**Form semantics:**
- `static formAssociated = true` gives it `form`, `name`, `validity`, `checkValidity`, `reportValidity`, `setCustomValidity` and `formResetCallback`, which restores the initial value and clears history.
- `required` is evaluated through a hidden `<textarea>` so native validation messages are used.
- Extensions contribute validity flags via `setEditorValidity`; `AttachmentsExtension` blocks submit while uploads are pending.

**Modes:**
- `richText: false` switches to plain text with no toolbar.
- `multiLine: false` or the `single-line` attribute swallows Enter; Ctrl/Cmd+Enter is always swallowed so host apps can bind submit.
- There is no built-in disabled/readonly support.

**Turbo:**
- `turbo:before-cache` tears the editor down unless it's inside `[data-turbo-permanent]`.
- `disconnectedCallback` stashes `valueBeforeDisconnect` so a move or morph keeps content.
- If a morph rewrites the `connected` attribute, the element reconnects.

**Public API:**
- Properties: `value`, `toString()` (readable text; mentions render as their label), `isEmpty`, `isBlank`, `canUndo`, `canRedo`, `focus()`, `editor` (the raw Lexical editor), `contents`, `selection`, `toolbarElement`.
- Adapter methods: `registerAdapter`, `freezeSelection`, `thawSelection`.
- Events: `lexxy:initialize | change | focus | blur | file-accept (cancelable) | insert-link | insert-markdown | upload-start | upload-progress | upload-end | attributes-change | editor-initialized | code-language-picker-open`.

## 5. Configuration

`src/config/lexxy.js` + `src/editor/configuration.js`.

- `Lexxy.configure({ global: {...}, default: {...}, myPreset: {...} })` deep-merges into the defaults.
- **Global options:** `attachmentTagName` (must match `config.action_text.attachment_tag_name` by hand), `attachmentContentTypeNamespace`, `authenticatedUploads`, `extensions`.
- **Per-editor options:** `toolbar`, `attachments`, `markdown`, `multiLine`, `richText`, `permittedAttachmentTypes`, `headings` (default `["h2","h3","h4"]`), `highlight.buttons` / `highlight.permit`.
- Resolution order: the `default` preset, then the element's `preset="…"` preset, then dasherized HTML attributes (`markdown="false"`, `permitted-attachment-types="image/png"`). Attribute values are JSON-parsed, with a fallback to the raw string. Only keys present in the default preset can be overridden.

## 6. The Lexical layer

**Extensions all the way down.** Lexical 0.44's extension system (`defineExtension`, `configExtension`, `dependencies`, `buildEditorFromExtensions`) merges `nodes`, `theme` and `html` across extensions. Note: `html.import` merges by tag with `Object.assign`, so one converter per tag survives. That is why `HighlightExtension` pushes its `<pre>` converter straight into `editor._htmlConversions`.

A Lexxy extension is a thin object around one of these:

```js
class MyExtension extends Lexxy.Extension {
  get enabled() { return this.editorConfig.get("myFeature") }
  get allowedElements() { return [ "mark" ] }          // extends the sanitizer allowlist
  get lexicalExtension() { return this.defineExtension({ name: "app/my-feature", register(editor) { … } }) }
  initializeToolbar(toolbar) { toolbar.append(button) } // tagged data-lexxy-extension, removed on reconnect
}
Lexxy.configure({ global: { extensions: [ MyExtension ] } })
```

**Built-in extensions:**

| Extension | What it does |
|-----------|--------------|
| ProvisionalParagraph | Invisible caret paragraphs between blocks you otherwise couldn't type between (never exported) |
| CodeHighlighting | Prism tokenization of `CodeNode`, re-applying highlight/link ranges after retokenizing |
| Highlight | Color/background-color text styles, `<mark>`-like format bit, canonicalizes pasted colors to configured palette via computed-style equality |
| TrixContent | Imports legacy Trix markup (`strong`/`em`/`del` spans, `pre[language]`) |
| Tables | `WrappedTableNode` replaces `TableNode`; workarounds for Lexical #8089/#8090; table string commands |
| RewritableHistory | Owns `HistoryExtension`; `REWRITE_HISTORY_COMMAND` patches nodes in every undo/redo snapshot (used so upload progress/completion doesn't create or break undo states) |
| Attachments | Attachment/upload/gallery nodes; unwrap-from-paragraph; gallery merge; Tab into caption; pending-upload validity |
| FormatEscape | Enter on an empty last line exits code blocks, list items and quotes (`EarlyEscape*` node replacements) |
| LinkOpener | Cmd/Ctrl-click and middle-click open links |
| PreventLexicalTripleClick | Works around lexical#4512 |
| CustomAttachmentDragAndDrop | Drag inline custom attachments (mentions) |
| LineSeparators | `\n`, U+2028 and U+2029 become `LineBreakNode`s |

**Custom nodes (`src/nodes`):**

| Node | Role |
|------|------|
| `ActionTextAttachmentNode` | Decorator. Imports `<action-text-attachment>`, `img` and `video`; exports canonical attachment markup with `presentation="gallery"`, caption and alt. Handles preview swap and `preview_status_url` polling. |
| `ActionTextAttachmentUploadNode` | Exists only during a `DirectUpload`; never exported. It swaps itself for the final node via the history rewrite and aborts the XHR if deleted. |
| `CustomActionTextAttachmentNode` | Inline decorator for SGID content (mentions etc.). Matches only when a `content` attribute is present; that inner HTML is sanitized strictly (`safeForXml`). |
| `ImageGalleryNode` | Element node for a `<div>` of attachments; self-normalizing transform. |
| `HorizontalDividerNode` | Renders `<figure><hr>`, exports `<hr>`. |
| `ProvisionalParagraphNode` | See ProvisionalParagraph. Its type string is misspelled `provisonal_paragraph` — don't "fix" it without a migration story for serialized JSON. |
| `EarlyEscapeCodeNode`, `EarlyEscapeListItemNode`, `WrappedTableNode` | Lexical node replacements. JSON type names differ from stock Lexical; HTML output is identical. |

## 7. Controllers (the OO surface over Lexical)

- **Contents** (`src/editor/contents.js`):
  - Inserts nodes through strategy objects (code block, shadow root, NodeSelection, list item, block container), each dodging a specific Lexical invariant (#99, #211, #212) or NodeSelection's delete-on-insert.
  - Also handles block formats (headings, quote, code, lists), links, prompt text replacement (`replaceTextBackUntil`) and upload entry points, including pending-upload handles for native apps.
- **Selection** (`src/editor/selection.js`): `getFormat()` feeds the toolbar and adapter. It also handles keyboard navigation around decorators: arrow keys, and Backspace selecting an attachment before deleting it.
- **Clipboard** (`src/editor/clipboard.js`) routes pastes:
  - Inside code: plain text.
  - A lone URL: link, plus `lexxy:insert-link`, which lets the host turn it into an embed attachment.
  - Plain text: markdown via an isolated `marked` instance (`breaks: true`, no indented code, unknown tags escaped), then `lexxy:insert-markdown`.
  - HTML: `PastedContentFormatter` (Office lists, Gmail quirks, style stripping), then import.
  - Anything else falls through to Lexical.
- **CommandDispatcher:** Lexical keys commands by identity, so Lexxy registers plain strings. The toolbar's `data-command="bold"` becomes `editor.dispatchCommand("bold")` inside an update. It also handles Tab indent/outdent, the inline-code arrow exit, and external file drops.

## 8. Sanitization — three independent gates

| Gate | Where | What |
|------|-------|------|
| Client | `src/config/dom_purify.js` and `src/editor/sanitizer.js` | Own DOMPurify instance with a lazy `lexxy` Trusted Types policy. Allowed tags = the tags this editor can import plus extension `allowedElements`. Attributes: alt, class, contenteditable, href, src, style, title. `style` is reduced to color and background-color. `data-controller` and `data-action` are forbidden. `data:` URLs are allowed only on the attachment tag. |
| Server (render) | `ActionText::ContentHelper`, extended in `lib/lexxy/engine.rb` | Adds tags `video audio source embed table tbody tr th td` and attributes `controls poster data-language style value start`; adds `var()` to Loofah's CSS functions. Appended in `on_load(:action_text_content)`, so a host app that assigns `allowed_tags` later overwrites Lexxy's additions. |
| Display | `highlightCode()` (exported helper) | Prism-highlights `pre[data-language]` on rendered pages. |

Action Text does **not** sanitize on save. The stored HTML is whatever the client posted after canonicalization and minification; sanitization happens at render time. Any new markup must survive all three gates (AGENTS.md "Action Text Persistence").

## 9. Rails / Action Text integration

**Rails main (8.2): the adapter path.**
- `Lexxy.supports_editor_adapter?` checks that `ActionText::Editor#editor_tag` accepts a block (rails/rails#56926).
- The engine then registers `config.action_text.editors[:lexxy]` and sets `config.action_text.editor = :lexxy` before Rails' `action_text.editors` initializer. Rails' Configurator requires `action_text/editor/lexxy_editor` and constantizes `LexxyEditor`.
- `LexxyEditor::Tag#render_in` adds `data-action-text-supports-alt`. It also unwraps the `html_safe` value to a String so the `value` attribute is escaped (#749).
- `Editor::Tag` renders `<lexxy-editor class="lexxy-content">` with the block content (e.g. `<lexxy-prompt>`) as children and no hidden input. The element is its own form control.

**Rails 8.0/8.1: the monkey-patch path.**
- Lexxy prepends into `ActionText::TagHelper`, `FormHelper`, `FormBuilder` and `Tags::ActionText`, and aliases `rich_textarea` / `rich_text_area` to its versions.
- Opt out with `config.lexxy.override_action_text_defaults = false`, then use `lexxy_rich_textarea` explicitly.
- It reads `body_before_type_cast` rather than `to_editor_html`, which would emit Trix figures on those versions. It JSON-encodes each rendered custom attachable into `content`; the JS `parseAttachmentContent` accepts JSON or raw HTML, so both paths load.

**Attachables:**
- Lexxy wraps `Attachable.from_node` so a would-be `MissingAttachable` retries as `ActionText::Attachables::RemoteVideo` (`video/*` with a `url`).
- It overrides `_remote_image` to add `alt`.
- It prepends `ActiveStorage::BlobWithPreviewUrl`, so a previewable non-image blob's JSON (the direct-upload response) includes `previewable: true` plus a preview representation `url`. That's how PDFs and videos get thumbnails in the editor.

**Custom attachables such as mentions:** include `ActionText::Attachable` and give it a content type, e.g. `application/vnd.actiontext.mention`.
- In the editor they arrive as `<lexxy-prompt-item sgid=…>` with `<template type="editor">`.
- They are stored as `<action-text-attachment sgid content-type>`.
- They render through `to_attachable_partial_path`.
- On re-edit they come back with `content` rendered from `to_editor_content_attachment_partial_path`.

**Uploads:**
- Lexxy does not use `@rails/actiontext`'s JS, which is Trix-event-only. It dynamically imports `@rails/activestorage` and uses `DirectUpload` against `data-direct-upload-url`.
- It reads `attachable_sgid`, `signed_id`, `url`, `previewable` and `preview_status_url` from the blob JSON.
- On save, Action Text's `before_validation` turns blob attachables into `embeds`.

**Migration from Trix:** no data migration is needed, and the rake task file is an empty stub. Both editors persist canonical Action Text HTML, and `TrixContentExtension` imports Trix-specific inline styling. Trix ↔ Lexxy interop is covered by `test/system/trix/*`.

## 10. End-to-end round trip

1. **Render form:** `to_editor_html` produces the `<lexxy-editor value=…>` markup, with custom attachables carrying a rendered `content`.
2. **Connect:** HTML is imported into Lexical nodes. Attachments with `content` become `CustomActionTextAttachmentNode`; those with `sgid`/`url` become `ActionTextAttachmentNode`.
3. **Edit:** each update re-exports and sanitizes HTML, calls `setFormValue` and fires `lexxy:change`. Uploads go through `DirectUpload`, then an upload node, then the history rewrite, then an attachment node carrying the `sgid`.
4. **Submit:** `post[body]` holds the sanitized canonical HTML.
5. **Save:** `Content.new` canonicalizes (identity for Lexxy), empties attachment inner HTML and sets `embeds`.
6. **Show:** each attachment is rendered via its partial, the result is sanitized with the extended allowlist, then `highlightCode()` runs client-side.
7. **Re-edit:** back to step 1, with `content` re-rendered from the live record, so mention names and avatars are always fresh.

## 11. UI chrome

- **`<lexxy-toolbar>`:**
  - Buttons carry `data-command`. `data-hotkey` binds shortcuts, though only Cmd/Ctrl+K for links by default; bold, italic and similar come from Lexical's own key handling.
  - An update listener keeps `aria-pressed` and `aria-disabled` in sync.
  - A ResizeObserver moves trailing buttons into an overflow menu.
  - `toolbar="some-id"` points the editor at an external toolbar; `toolbar="false"` removes it.
- **Dropdowns** (heading, highlight, link) share `ToolbarDropdown`: focus trap, Escape, arrow navigation.
- **`<lexxy-prompt>`:**
  - Attributes: `trigger`, `src`, `remote-filtering`, `name`, `empty-results`, `insert-editable-text`, `supports-space-in-searches`, `only-at`, `vertical-direction`.
  - Sources: inline items, `src` fetched once, or `?filter=` with a 200 ms debounce.
  - Filtering is diacritic-insensitive, capped at 100 results.
  - Races are guarded by a request-id counter.
  - Keys are captured at CRITICAL priority.
- **Accessibility:** Shift+Tab reaches the toolbar; Alt+F10 reaches the attachment and table toolbars; Alt+Shift+Arrow moves attachments. `aria-*` on the host is mirrored to the contenteditable. Announcements use `document.ariaNotify`, falling back to `<lexxy-live-region>`.
- **CSS:** four stylesheets, every selector wrapped in `:where()` (zero specificity), tokens in `lexxy-variables.css` (`--highlight-N`, `--highlight-bg-N`, …). There is no dark theme; `home/…/sandbox.css` is an example.

## 12. Build, distribution, tests

- **Gem:** `rollup.config.mjs` builds `app/assets/javascript/lexxy.js` (plus min/gz/br), bundling everything except `@rails/activestorage`. The output is gitignored; `ext/Rakefile` builds it for git installs. Hosts pin `lexxy` and `@rails/activestorage` in importmap.
- **npm** (`@37signals/lexxy`): `rollup.config.npm.mjs` emits `dist/lexxy.esm.js` with Lexical, DOMPurify, marked and Prism external, plus a `./helpers` entry (`highlightCode` + Prism) for render-only pages.
- **Exports:** the nodes, `REWRITE_HISTORY_COMMAND`, `highlightCode`, `highlightElement`, `NativeAdapter`, `EditorSanitizer`, `configure`, `Extension`, and `Lexical` (the whole namespace, so extensions share one Lexical instance).
- **Tests:**
  - Vitest (`test/javascript`, jsdom) covers helpers and the native bridge.
  - Playwright (`test/browser`) runs against source via Vite and static fixtures, with no Rails and mocked Active Storage routes.
  - Capybara (`test/system`) runs the dummy app with the built bundle and covers the persistence round trips and Trix interop.
  - Benchmarks: `yarn benchmark:browser`, with CI comparison against `main`.

## 13. Sharp edges found during the review

- `RichTextExtension` is pulled in as a dependency of `HighlightExtension` and `registerRichText` is also called directly (`editor.js#registerComponents`), so rich-text handlers are registered twice. This appears harmless.
- `HighlightExtension`'s default config shape doesn't match the keys it reads (`buttons`/`permit`); it works only because the preset config is merged in.
- `prompt.js` checks an `initialPrompt` flag that is never set.
- `debounceAsync` leaves superseded promises pending forever; correctness relies on the prompt's request-id counter.
- The Action Text layout still wraps rendered content in `trix-content`; Lexxy's class is `lexxy-content`.
- `attachmentTagName` on the client and `config.action_text.attachment_tag_name` on the server aren't synced automatically.
- `preview_status_url` is read by the JS but not provided by the gem; hosts must add it.
- Docs drift:
  - `home/docs/index.md` still pins `~> 0.9.21`.
  - `css-setup.md` gives the wrong variables path.
  - The multiple-attachments prompt example uses `<% %>` instead of `<%= %>`.
  - Several events and properties are undocumented: `attributes-change`, `editor-initialized`, `value`, `isEmpty`, `single-line`.
  - The release post mentions "preliminary Trusted Types support", but the docs say enforced Trusted Types is not yet supported.
