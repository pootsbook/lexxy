# Lexxy — notes from website (lexxy.dev), docs, and 1.0 release post

Sources and access status (2026-09-29):
- Local site source `home` (Jekyll, just-the-docs theme): read in full (`index.html`, `sandbox.html`, `attachments-sw.js`, `_config.yml`, `_layouts/landing.html`, `_includes/*`, all `docs/*.md` and `docs/prompts/*.md`).
- **https://lexxy.dev**: BLOCKED by the egress proxy (WebFetch and curl both 403). Live-vs-local diff NOT possible. Search-engine title for the live site is "Lexxy — A modern rich text editor for Rails", which matches `_config.yml` (`title: Lexxy`, `description: A modern rich text editor for Rails`).
- **https://dev.37signals.com/lexxy-1-0/** ("Lexxy 1.0 is here"): BLOCKED (egress proxy); web.archive.org and daily.dev also blocked. Blog claims below come ONLY from web-search snippets/summaries, so treat wording as paraphrase, not verbatim quotes. GitHub release `v1.0.0` notes could not be read (basecamp/lexxy not configured for the GitHub MCP; `gh` not installed).
- Local repo is at `Bump version to 1.0.0` (commit ea8ab63); `lib/lexxy/version.rb` and `package.json` both = `1.0.0`.

---

## 1. The 1.0 release post (dev.37signals.com/lexxy-1-0/) — claims via search summaries

Title: "Lexxy 1.0 is here" (37signals Dev blog). An earlier beta announcement exists: "Lexxy: A new rich text editor for Rails" (dev.37signals.com/announcing-lexxy-a-new-rich-text-editor-for-rails/, ~Sept 2025; HN item 45134121). Rails World 2026 has a session "Lexxy: a new text editor for Action Text" by Jorge Manrubia.

Claims:
- Lexxy 1.0 is a rich text editor for Rails built on Meta's **Lexical**. "It already powers Basecamp, Fizzy and many others, and it will become the default editor in Rails."
- **Why replace Trix**: Trix has been 37signals' editor since 2015 and every Rails app's editor since Action Text shipped in Rails 6; "small and reliable", "served millions of people for a decade". But customers kept asking for features like **tables** or **code highlighting**, and they "kept struggling to deliver them". Trix's **flat document model** (a flat list of blocks; a block can never contain another block) could not support tables. Trix's reliance on raw `contenteditable` became a maintenance burden across browser/OS updates.
- **Why Lexical**: a proper node-tree document model; Lexical's architecture plus its massive production user base (WhatsApp/Instagram etc.) made it a better long-term bet.
- **Headline features**: tables, Markdown input, syntax-highlighted code blocks, image galleries, prompts (mentions/emoji), extensibility via Lexical's extension mechanism, improved accessibility, stronger security (sanitization, allow-listed attachments, *preliminary* Trusted Types support).
- **Performance**: in a 10,000-word document, Lexxy processes a keystroke in **4 ms vs 38 ms for Trix**.
- **Action Text native**: emits Action Text's canonical markup, so existing content and attachments stay compatible. Ships with **Rails 8.2**; switching from Trix is a one-line config change: `config.action_text.editor = :lexxy`.
- Rails side: a merged Rails PR (rails/rails#51238) introduces an `ActionText::Editor` base class with adapters for Trix and Lexxy — Action Text becomes editor-agnostic. Trix remains functional but (per summaries) no longer receives updates from 37signals.
- DHH (X): "Lexxy is one of the big upgrades in Basecamp 5. Finally we have tables! We have markdown! We have live syntax highlighting! Trix served us well for many years, but Lexxy's arrival is a massive upgrade."
- Roadmap/"what's next": not retrievable. The docs themselves flag: extensions API is experimental; Trusted Types enforcement not yet supported (demand-driven).

---

## 2. Website landing page (`home/index.html`)

- Tagline: "A modern rich text editor for **Rails**".
- Lead: "Lexxy powers Basecamp and hundreds of other products." / "Clean HTML, Markdown shortcuts, code highlighting, attachments, accessibility and more, all wired straight into Action Text."
- Buttons: "Read the docs" (/docs/), "View on GitHub" (github.com/basecamp/lexxy).
- Live hero editor: `<lexxy-editor class="lexxy-content" placeholder="Try out Lexxy! Type, format, paste a link, or hit : to drop in an emoji..." data-direct-upload-url="/rails/active_storage/direct_uploads" data-blob-url-template="/rails/active_storage/blobs/:signed_id/:filename">` with an emoji `<lexxy-prompt trigger=":" insert-editable-text>` (8 items: Joy, Heart, Thumbs Up, Fire, Party, Rocket, 100, Check).
- "used-by" logos section (empty div; logos come from CSS / `assets/images/logos.png`, `logo-basecamp.png`).
- Features section "Everything you'd expect, done right — A focused set of features that respect your markup and your users.":
  1. Built on Lexical — Meta's extensible text-editor framework
  2. Clean HTML semantics — "Paragraphs are real `<p>` tags, as they should be"
  3. Markdown support — inline shortcuts and auto-formatting on paste
  4. Code highlighting — real-time syntax highlighting for fenced code blocks as you type
  5. Smart links — paste a URL over selected text to turn it into a link
  6. Attachment previews — PDFs and videos inside the editor
  7. Image galleries — grid, full drag-n-drop
  8. Tables — "Best-in-class UX for creating and editing tables"
  9. Configurable prompts — mentions and interactive prompts, flexible loading/filtering
  10. Action Text native — "Generates the canonical HTML Action Text expects — drop-in for Trix"
  11. Extendable — extensions
  12. Customizable — "Written in vanilla JavaScript and CSS"
- Layout (`_layouts/landing.html`) loads Lexxy from CDN: `<link rel="stylesheet" href="https://esm.sh/@37signals/lexxy@latest/dist/stylesheets/lexxy.css">` and `import * as Lexxy from "https://esm.sh/@37signals/lexxy@latest"`, then registers the service worker `/attachments-sw.js`. Font: Lexend (Google Fonts). The site always runs `@latest` npm, not the repo's source.

## 3. Sandbox (`home/sandbox.html`, permalink `/sandbox/`)

- "Try Lexxy in a Sandbox". Toggle "Show HTML output" (persisted in `localStorage` key `lexxy-sandbox-show-html-output`).
- Editor pre-seeded via `value='...'` with: h2/h3, a `<ul>` of feature bullets (`<li value="1">`…), `<mark style="color: var(--highlight-1);">`/`background-color: var(--highlight-bg-6)` highlights, `<pre data-language="css" data-highlight-language="css">` code, and a table `<figure class="lexxy-content__table-wrapper"><table>… <th class="lexxy-content__table-cell--header"><p>…</p></th>`. This shows Lexxy's canonical output shapes (marks with inline style, code as `<pre data-language>`, tables wrapped in a figure, cells containing `<p>`).
- 18-item emoji prompt (`trigger=":" insert-editable-text`).
- On `lexxy:change` (debounced 150 ms), reads `editor.value`, formats with Prettier 3.6.2 (HTML parser, printWidth 80) and highlights with Prism 1.30.0 (both dynamically imported from esm.sh), renders into `<pre class="try__output lexxy-content">`.

## 4. `attachments-sw.js` — how the demo uploads work without a server

Service worker that mocks Active Storage Direct Upload in-browser (files kept in an in-memory `Map`, lost on SW restart):
- `POST …/rails/active_storage/direct_uploads` → returns blob JSON: `id`, `key: demo-key-N`, `filename`, `content_type`, `byte_size`, `checksum`, `signed_id: demo-signed-id-N`, `attachable_sgid: demo-sgid-N`, `direct_upload: { url: /rails/active_storage/disk/<signedId>, headers: {Content-Type} }`.
- `PUT …/rails/active_storage/disk/<signedId>` → stores bytes, 204.
- `GET …/rails/active_storage/blobs/<signedId>/…` → serves stored bytes (404 otherwise).
- `skipWaiting` + `clients.claim` so it takes effect immediately. Note it does not return `previewable`/`url`, so PDF/video previews don't render in the demo (images are served via the blob URL template).

---

## 5. Installation (docs/index.md)

- Gemfile: docs say `gem 'lexxy', '~> 0.9.21'` (STALE — repo is 1.0.0), then `bundle install`.
- **Import maps + propshaft**:
  ```ruby
  pin "lexxy", to: "lexxy.js"
  pin "@rails/activestorage", to: "activestorage.esm.js" # to support attachments
  ```
  `import "lexxy"` in `app/javascript/application.js`.
- **JS bundlers** (jsbundling-rails, esbuild, webpack…): `yarn add @37signals/lexxy` and `yarn add @rails/activestorage`; `import "@37signals/lexxy"`.
- **CDN (esm.sh)**: `<link rel="stylesheet" href="https://unpkg.com/@37signals/lexxy@latest/dist/stylesheets/lexxy.css">` + `import * as Lexxy from "https://esm.sh/@37signals/lexxy@latest"` (pin a version). Loads all dependencies.
- **Action Text integration**:
  - Rails 8.2+: Lexxy registered as an Action Text editor adapter and set as default by the gem (`config.action_text.editor = :lexxy`).
  - Rails 8.0/8.1: gem overrides Action Text form helpers so `form.rich_text_area` renders Lexxy. Opt out: `config.lexxy.override_action_text_defaults = false`; then use `lexxy_rich_textarea_tag` and `form.lexxy_rich_text_area` explicitly (incremental migration; mix with Trix).
- npm vs asset pipeline difference (from CSP section): via npm `dompurify` is external (shared module, Lexxy creates its own instance); via Rails asset pipeline `lexxy.js` has DOMPurify inlined.
- Submodule for splitting bundles: `import { highlightCode } from "@37signals/lexxy/helpers"`.

## 6. CSS setup (docs/css-setup.md)

- `<%= stylesheet_link_tag "lexxy" %>`; or copy the CSS and adapt.
- All colors are CSS variables in "`app/stylesheets/lexxy-variables.css`" (doc path; actual repo path is `app/assets/stylesheets/lexxy-variables.css`). Dark-mode example: `test/dummy/app/assets/stylesheets/sandbox.css`.
- Stylesheets in gem: `lexxy.css`, `lexxy-variables.css`, `lexxy-editor.css`, `lexxy-content.css`.
- Variables (from source): `--lexxy-color-ink`, `-ink-medium`, `-ink-light`, `-ink-lighter`, `-ink-lightest`, `-ink-inverted`, `--lexxy-color-canvas`, `-text`, `-text-subtle`, `-link`, `-accent-dark/-medium/-light/-lightest`, `-selected`, `-selected-50`, `-selected-dark`, `-selected-hover`, `-red/-green/-blue/-purple`, `-code-bg`, `-code-token-{att,comment,function,operator,property,punctuation,selector,variable}`, `-floating-controls-separator`, `-table-cell-{add,border,remove,selected,selected-bg,selected-border,toggle}`, `-table-header-bg`; `--lexxy-font-base`, `--lexxy-font-mono`, `--lexxy-text-small`, `--lexxy-radius`, `--lexxy-shadow`, `--lexxy-content-margin`, `--lexxy-focus-ring-{color,offset,size}`, `--lexxy-toolbar-button-size`, `--lexxy-table-cell-add-size`, `--lexxy-z-popup`; highlight palette `--highlight-1..9`, `--highlight-bg-1..9`.
- Rendered content: override `app/views/layouts/action_text/contents/_content.html.erb` with `<div class="lexxy-content"><%= yield -%></div>`.
- Syntax highlighting in rendered views: call `highlightCode()` (e.g. Stimulus `syntax-highlight` controller on connect; `data-controller="syntax-highlight"` on the content wrapper). Imports: `import { highlightCode } from "lexxy"` / `"@37signals/lexxy"` / `"@37signals/lexxy/helpers"`.

## 7. Usage & forms (docs/usage.md)

- Rails: `form.rich_text_area :content` inside `form_with`.
- Vanilla: `<lexxy-editor name="post[body]">` — "first-class form control" (form-associated custom element, `static formAssociated = true`).
- Native validation: `editor.setCustomValidity(msg)`, `editor.reportValidity()`, `editor.checkValidity()`, `editor.validationMessage`, `editor.validity`. Non-empty custom message blocks submission; clear with `""`. Custom errors persist through edits/form reset until cleared; clearing doesn't remove `required` or pending-upload constraints (pending uploads block submission).

## 8. Configuration (docs/configuration.md)

Resolution: **default** preset → named **preset** (extends default, chosen with `preset="name"` attribute) → **HTML attributes** on the element (highest). `import * as Lexxy from "lexxy"`; call `Lexxy.configure(...)` **synchronously right after import** — elements are defined in a `setTimeout(defineElements, 0)` after the import's call stack.

```js
Lexxy.configure({ default: { toolbar: false } })            // all editors
Lexxy.configure({ simple: { richText: false } })             // <lexxy-editor preset="simple">
// <lexxy-editor preset="simple" rich-text="true">           // attribute override
Lexxy.configure({ global: { attachmentTagName: "bc-attachment" } })
```

Attribute mechanics (source): any key of the default preset can be set as a dasherized attribute (`richText` → `rich-text`, `multiLine` → `multi-line`, `permittedAttachmentTypes` → `permitted-attachment-types`); value is `JSON.parse`d, falling back to the raw string (so `headings='["h2","h3"]'`, `toolbar="false"`, `toolbar="my-toolbar-id"` work).

Editor options (preset/attribute), defaults from `src/config/lexxy.js`:
- `toolbar` (default `{ upload: "both" }`): `false` disables; a string = ID of an external `<lexxy-toolbar>` element; object configures buttons.
  - `toolbar.upload`: `"file"` | `"image"` | `"both"` (default). Image button uses `accept="image/*,video/*"` (native photo/video pickers on iOS/Android).
- `attachments` (default `true`): `false` disables completely (incl. paste, drag & drop).
- `markdown` (default `true`).
- `multiLine` (default `true`): `false` = single line. Also a separate `single-line` attribute exists (`isSingleLineMode`).
- `permittedAttachmentTypes` (default `null` = any): allowlist of content types; attribute is space-separated, e.g. `permitted-attachment-types="application/vnd.basecamp.mention application/vnd.basecamp.opengraph-embed"`; arrays accepted in JS.
- `richText` (default `true`).
- `headings` (default `["h2","h3","h4"]`); `[]` removes heading options (dropdown keeps "Normal" and "Clear formatting").
- `highlight` (see §12).
- Standard attrs: `placeholder`, `name`, `value`, `required`, `disabled`, `autofocus`, `autocapitalize`, `aria-*`.
- Undocumented-but-used attrs: `data-direct-upload-url`, `data-blob-url-template` (Rails helper sets these; the landing page sets them manually).
- Toolbar counts as part of the editor for focus/blur; a custom toolbar that registers handlers should expose `dispose()` (called on editor disconnect).

Global options (`Lexxy.configure({ global: {...} })`), defaults:
- `attachmentTagName` (default `"action-text-attachment"`) — global only.
- `attachmentContentTypeNamespace` (default `"actiontext"` → `application/vnd.actiontext.<type>`).
- `authenticatedUploads` (default `false`) — sets `withCredentials: true` on Active Storage upload requests; configure cookie domain + CORS/CSRF.
- `extensions` (default `[]`) — array of `Lexxy.Extension` subclasses.

### Content Security Policy / Trusted Types
- Lexxy uses its **own DOMPurify instance**, so app DOMPurify config/hooks are untouched.
- Every DOMPurify instance requests a Trusted Types policy named `dompurify`; duplicates are refused and the loser **silently returns `""`** (no error). So Lexxy requests policy name **`lexxy`**. Add it: `Content-Security-Policy: require-trusted-types-for 'script'; trusted-types dompurify lexxy`, Rails: `policy.trusted_types "dompurify", "lexxy"` (strings, not symbols — symbols raise `ArgumentError`) + `policy.require_trusted_types_for :script`.
- If not allowlisted: Lexxy catches, console-warns, signs nothing; never falls back to `dompurify`. Alternative: `trusted-types dompurify allow-duplicates`.
- **Lexxy does NOT yet work under enforced Trusted Types**: unwrapped sinks — `parseHtml` and `createElement` (`helpers/html_helper.js`; wrapped-table figure, table tools row/col count), `highlightElement` (`helpers/code_highlighting_helper.js`; public `highlightCode`/`highlightElement` also throw), `insertAdjacentHTML` in `nodes/custom_action_text_attachment_node.js`, toolbar/dropdown/delete-button `innerHTML` in `elements/`. Editor throws on connect. "Please open an issue if you need it."

## 9. Public JS API

Package exports (`src/index.js`): all nodes (e.g. `ActionTextAttachmentNode`), commands (`REWRITE_HISTORY_COMMAND`), `highlightCode`, `highlightElement`, `NativeAdapter`, `EditorSanitizer`, `configure`, `Extension`, `Lexical` (whole `lexical` package re-exported: `import { Lexical } from "@37signals/lexxy"`).

`<lexxy-editor>` (from docs + source `src/elements/editor.js`; docs only document the validation subset):
- Properties: `value` (get/set HTML), `form`, `name`, `required`, `validity`, `validationMessage`, `isEmpty`, `isBlank`, `hasOpenPrompt`, `preset`, `supportsAttachments`, `supportsMarkdown`, `supportsMultiLine`, `supportsRichText`, `isSingleLineMode`, `permittedAttachmentTypes`, `directUploadUrl`, `blobUrlTemplate`, `toolbarElement`, `canUndo`, `canRedo`, `config` (`editorConfig.get(path)`), `uploadRequests`, `static commands = ["bold","italic","strikethrough"]`.
- Methods: `focus()`, `toString()` (plain text), `setCustomValidity()`, `checkValidity()`, `reportValidity()`, `permitsAttachmentContentType(ct)`, `acceptsFile(file)`, `announce(message)` (live region), `freezeSelection()`/`thawSelection()`, `registerAdapter(adapter)`.
- `observedAttributes`: `autocapitalize`, `connected`, `required`. Form reset supported (`formResetCallback`).

### Events (docs/events.md) — all dispatched on `<lexxy-editor>`
- `lexxy:initialize` — attached and ready.
- `lexxy:focus` / `lexxy:blur` — editor + toolbar (and children) considered one unit.
- `lexxy:change` — content changed.
- `lexxy:file-accept` — `detail.file`; `preventDefault()` cancels. Lexxy itself uses it to enforce `permittedAttachmentTypes`.
- `lexxy:upload-start` — `detail.file`.
- `lexxy:upload-progress` — `detail.file`, `detail.progress` (0–100).
- `lexxy:upload-end` — `detail.file`, `detail.error` (`null` on success).
- `lexxy:insert-link` — plain-text link pasted; `detail.url`, `detail.replaceLinkWith(html, options)`, `detail.insertBelowLink(html, options)`; options `{ attachment: true }` (non-editable) or `{ attachment: { sgid: "..." } }`. Docs example: link-unfurl Stimulus controller posting to an endpoint with `@rails/request.js`.
- `lexxy:insert-markdown` — before inserting converted Markdown; `detail.markdown`, `detail.document` (live, mutable DOM `Document`; `detail` is frozen; only sync handlers can mutate), `detail.addBlockSpacing()` (inserts `<p><br></p>` between top-level elements except after headings).
- Undocumented events in source: `lexxy:attributes-change`, `lexxy:editor-initialized`, `lexxy:code-language-picker-open`.

## 10. Extensions (docs/extensions.md) — "experimental and may evolve with no deprecation period"

- Subclass `Lexxy.Extension`; one instance per editor per `connectedCallback`: `new MyExt(lexxyElement)`; base provides `this.editorElement`, `this.editorConfig`. Custom constructors must `super(lexxyElement)`.
- `get enabled()` (optional, default true), `get lexicalExtension()` (return `this.defineExtension({...})`, wraps Lexical `defineExtension` — don't install your own `lexical`), `initializeToolbar(lexxyToolbar)`, `dispose()` (called on disconnect/reconnect; clean up listeners, observers, timers, inserted DOM, async state), `get allowedElements()`.
- `allowedElements`: tag names or `{ tag, attributes: [...], uriSafeSchemes: [...] }`, e.g. `{ tag: "bc-mention", attributes: ["gid"], uriSafeSchemes: ["gid"] }`. Schemes are editor-wide once allowed; executable schemes (`javascript:`, `data:`, `vbscript:`, `…script:`) can never be declared.
- Register: `Lexxy.configure({ global: { extensions: [MyLexxyExtension] }, default: { my_extension: {...} } })`.
- Nodes extensible: `import { ActionTextAttachmentNode } from "@37signals/lexxy"`.

## 11. Attachments (docs/attachments.md)

- Active Storage **Direct Upload** protocol; previews for previewable blobs (images, PDFs, videos).
- Alt text: "ALT" button in attachment toolbar; enabled only when Action Text supports `alt` attachment attribute (rails/rails#58337). If overriding partials: `_blob.html.erb` → `alt: blob.try(:alt)`; `action_text/attachables/_remote_image.html.erb` → `alt: remote_image.try(:alt)`.
- Upload response fields read: `signed_id`, `attachable_sgid`, `filename`, `content_type`, `byte_size`, `previewable`, `url` (required if previewable), `preview_status_url` (optional).
- **Deferred previews**: show file icon until ready.
  - Default: preload `url` once into off-screen `Image`; swap on load; keep icon on error; no retries/cache-busting. Doesn't work for backends returning placeholder images.
  - Opt-in: `preview_status_url` polled via `fetch` with exponential backoff (max 20 attempts), `credentials: "include"`. `2xx` = still generating; any other status = ready (or never); network error = retry. Body ignored. Preview URL hit exactly once afterwards.
- Galleries: images arranged in grid; keyboard/drag arrangement (see hotkeys). Custom attachments via Action Text SGIDs (prompts, `insertBelowLink` with `{attachment}`), custom tag name via `attachmentTagName`, remote images (`_remote_image` partial).

## 12. Highlighting (docs/highlighting.md)

- CSS vars `--highlight-1..9` (color) and `--highlight-bg-1..9` (background). Default buttons labelled Yellow, Orange, Red, Magenta, Purple, Blue, Green, Sand, Gray.
- `highlight.buttons.color` / `highlight.buttons["background-color"]`: arrays of CSS values or `{ value, label }` (label = accessible name).
- `highlight.permit.color` / `highlight.permit["background-color"]`: extra colors preserved on paste but not shown as buttons (paste styles are sanitized otherwise).
- Output markup: `<mark style="color: …; background-color: …">`. Menu groups "Text color" and "Background color", shows selected.

## 13. Prompts (docs/prompts*.md)

- `<lexxy-prompt>` placed inside the editor (in Rails: block to `form.rich_text_area :body do ... end`). Items are `<lexxy-prompt-item search="...">` with `<template type="menu">` and `<template type="editor">`.
- Two insertion modes: Action Text custom attachment (SGID) or free editable HTML (`insert-editable-text`).
- Sources: inline items, or `src` URL (loaded once, filtered locally), or `src` + `remote-filtering` (server filters per query).
- `<lexxy-prompt>` attributes: `trigger` (e.g. `@`, `#`, `by:`), `src`, `name` (content type `application/vnd.actiontext.<name>`; required unless `insert-editable-text`), `empty-results` (default "Nothing found"), `remote-filtering`, `insert-editable-text`, `supports-space-in-searches`, `only-at` (regex matched against text before trigger, auto-anchored at end; default `^|[ \n]`; paragraph breaks appear as `\n\n`; `only-at="^"` = first char only; `only-at=".*"` = anywhere), `vertical-direction` (`top`|`bottom`).
- `<lexxy-prompt-item>`: `search`, `sgid` (use `attachable_sgid`).
- `<template type="editor">`: `sgid`, `content-type` (override; default `application/vnd.{namespace}.{prompt-name}`). Multiple editor templates → multiple attachments (e.g. group mentions).
- Server side: model `include ActionText::Attachable`, `def content_type; "application/vnd.actiontext.mention"; end`; partial `app/views/people/_person.html.erb` (or `to_attachable_partial_path`); reuse the same partial in the editor template for consistency. Remote endpoint: controller renders `layout: false` list of `_prompt_item` partials.
- Prompt only activates if attachments enabled and its content type is within `permittedAttachmentTypes` (when set).
- Keyboard: Up/Down select; Enter/Tab insert; Space inserts (unless `supports-space-in-searches`); Comma inserts + comma; Escape closes. Works inside table cells; screen reader support.

## 14. Hotkeys (docs/hotkeys.md) (macOS: Option=Alt, Command=Ctrl)

- Toolbar: `Shift+Tab` from editor focuses toolbar; Left/Right, Home/End, Enter/Space, arrows in menus (wrap), Escape (returns to button if opened by keyboard, else editor).
- Formatting: `Ctrl+B`, `Ctrl+I`, `Ctrl+U`, `Ctrl+K` (link dialog), `Ctrl+Z`, `Ctrl+Shift+Z` (also `Ctrl+Y` on Win/Linux).
- Attachments: `Alt+F10` attachment toolbar; `Escape` back; `Tab` edit caption; `Alt+Shift+Up/Down` move above/below block; `Alt+Shift+Left/Right` reorder within gallery. Captions: `Escape`/`Shift+Tab` back to attachment, `Enter` continue after; changes kept. Moving an image toward an adjacent image creates a gallery; toward a gallery joins it; Up/Down within gallery removes it.
- Tables: Tab/Shift+Tab cells; Enter = same column next row (last row adds a row; empty last row exits table); Shift+Enter line break; Backspace in empty cell → previous cell; Backspace in first cell of empty row removes row; `Alt+F10` table tools (Left/Right, Home/End, Enter/Space, Escape).
- Prompts: see §13.

## 15. Accessibility (docs/accessibility.md)

- Label via `<label for>`, wrapping `<label>`, `aria-labelledby`, `aria-label`. Descriptions via `aria-describedby` (wins) or `aria-description` (not combined). Rails: `aria: { describedby: ... }`.
- `required` → auto `aria-required`. Validation sets `aria-invalid="true"` after submit/checkValidity/reportValidity (not for untouched fields; cleared on reset). Explicit `aria-invalid` + `aria-errormessage` override.
- All `aria-*` on `<lexxy-editor>` forwarded to the editable textbox (incl. later changes/removals); removing overrides restores defaults. `aria-multiline` matches `multiLine`/`single-line`. Prompts manage `aria-controls`, `aria-activedescendant`, `aria-haspopup`.
- Focus indicators; semantic headings/lists/table headers; table header rows/columns toggle; attachments described by caption/alt/filename; moves announced via live region; mention names readable.

## 16. Markdown

- `markdown` option (default on): inline shortcuts (Lexical `TRANSFORMERS` + horizontal divider) and paste conversion; `lexxy:insert-markdown` hook. Code blocks via fenced markdown get live Prism highlighting; output `<pre data-language="…" data-highlight-language="…">`.

## 17. Development/site facts (docs/development.md)

- `bin/setup`, `bin/dev` (sandbox at http://lexxy.localhost:3000, CRUD at /posts; `PORT=3100 bin/dev`). Unreleased QA: `yarn add git+https://github.com/basecamp/lexxy.git#<sha>` (not the `basecamp/lexxy#ref` shorthand — Yarn 1 skips `prepare`, no `dist/`).
- Tests: Vitest (`yarn test`), Playwright across Chromium/Firefox/WebKit (`yarn test:browser[:chromium|:firefox|:webkit|:headed]`), Capybara (`bin/rails test:all`), lint (`bin/rubocop`, `yarn lint`).
- Benchmarks: `yarn benchmark:browser` (scenarios `bootstrap-empty-editor`, `bootstrap-many-editors`, `load-large-content`, `load-very-large-table`, `load-many-attachments`), compare script, CI workflow.
- Release: gem `rake release`, npm `yarn release`, GitHub release ("While in beta we are flagging the releases as pre-release" — stale at 1.0).
- Site: `cd home && bundle exec jekyll serve` (localhost:4000; /docs/, /sandbox/).

## 18. Discrepancies / surprises

1. docs/index.md pins `gem 'lexxy', '~> 0.9.21'` while the repo is 1.0.0.
2. development.md still says releases are pre-release "while in beta".
3. css-setup.md path `app/stylesheets/lexxy-variables.css` vs real `app/assets/stylesheets/lexxy-variables.css`.
4. CDN snippet uses unpkg for CSS, but the site layout uses esm.sh for CSS.
5. Blog advertises "preliminary Trusted Types support", but docs explicitly say Lexxy "does not yet work under enforced Trusted Types" (only the policy-name collision is solved).
6. Events doc omits `lexxy:attributes-change`, `lexxy:editor-initialized`, `lexxy:code-language-picker-open`; docs don't document `value`, `toString()`, `isEmpty`, `isBlank`, `data-direct-upload-url`, `data-blob-url-template`, `single-line`, or `<lexxy-toolbar>` markup/customization.
7. Blog/Rails: 8.2 makes Lexxy the default via `config.action_text.editor = :lexxy`; docs say the gem sets this itself on 8.2 — "default in Rails" per blog vs "gem sets it" per docs.
8. Landing says "hundreds of other products"; blog summary says "Basecamp, Fizzy and many others".
9. inline-attachments doc says "Two important additional notes" but lists three bullets; multiple-attachments example uses `<% ... %>` (no `=`), so the sgid would not be output — a doc bug.
10. The demo service worker omits `previewable`/`url`, so PDF/video previews don't show on lexxy.dev.
