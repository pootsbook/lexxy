# Lexxy deep-dive: extensions, nodes, UI elements, styling, build, tests

Paths are relative to the repo root. Lexical ref source: `facebook/lexical` tag v0.44.0, `packages/`. Lexxy depends on `lexical` + `@lexical/*` `^0.44.0` (package.json:60-74).

---------------------------------------------------------------------------------------------------

## 1. Extension system

### 1.1 Lexical's Extension API (what Lexxy builds on)

- `defineExtension(ext)` is an identity function for type inference (`lexical/src/extension-core/defineExtension.ts:54-62`). An extension is a plain object; **must be a stable reference** per build; `name` is the only required key and must be unique per editor.
- `configExtension(ext, partialConfig, ...)` returns the tuple `[ext, config, ...]` (defineExtension.ts:91-99). A tuple can be passed anywhere an extension can (dependencies array, `buildEditorFromExtensions` args). Configs merged via `ext.mergeConfig` or default `shallowMergeConfig` (lexical/src/extension-core/shallowMergeConfig.ts:17).
- `declarePeerDependency(name, config?)` (defineExtension.ts:127) – optional, by-name deps; loops allowed. `conflictsWith: [names]` for early errors (e.g. RichText vs PlainText).
- Keys on an extension (docs: `lexical-website/docs/extensions/defining-extensions.md`):
  - merged editor-config keys: `nodes` (classes or `{replace, with, withKlass}` replacement objects; can be array or thunk), `html` (`import` map merged by `Object.assign` → **one converter per tag per whole editor**; `export` Map merged), `theme` (deep merged).
  - root-ish keys (last one wins): `$initialEditorState`, `namespace`, `editable`, `onError`, `parentEditor`, `disableEvents`.
  - phases: `config` (defaults) → `mergeConfig` → `init` → `build` (returns `output`, often `namedSignals(config)`) → `register(editor, config, state)` (after createEditor; return a dispose fn) → `afterRegistration` (all commands registered; `InitialStateExtension` applies `$initialEditorState` here).
  - `state.getDependency(Ext).output`, `state.getOutput()`, `state.getInit()`.
- `buildEditorFromExtensions(...exts)` (`lexical-extension/src/LexicalBuilder.ts:80-84`): always prepends `InitialStateExtension` (LexicalBuilder.ts:138-146), topologically sorts, builds `createEditor` args by merging (`buildCreateEditorArgs`, LexicalBuilder.ts:404-485 — note node-replacement conflict invariant: two extensions can't replace the same node class, ~L437-447), runs each rep's `build`, then `register`, then `afterRegistration`. Returns editor with `dispose()` (runs all cleanups + `setRootElement(null)`) (LexicalBuilder.ts:193-209).
- How `html.import` reaches the parser: core `initializeConversionCache` (lexical/src/LexicalEditor.ts:603-638) builds `Map<tag, converterFn[]>` from each node's `static importDOM()` plus `html.import` (additionalConversions). At import time the highest-priority non-null conversion wins.
- Relevant built-ins: `HistoryExtension` (`lexical-history/src/index.ts:565-590`, config `{delay:300, createInitialHistoryState, disabled: typeof window==='undefined', now}`; output signals incl. `historyState`), `RichTextExtension` (`lexical-rich-text/src/index.ts:1148-1154`: `conflictsWith ['@lexical/plain-text']`, deps `[DragonExtension]`, nodes `HeadingNode, QuoteNode`, `register: registerRichText`).
- Node `$config()` API (used by several Lexxy nodes): `$config(){ return this.config("type", { extends: Base, importDOM?, $transform?, stateConfigs? }) }` (lexical/src/LexicalNode.ts:98-163, 500-512). Replaces `getType/clone/importJSON` boilerplate; `$transform` is a node-level transform.

### 1.2 How Lexxy builds the editor

- `<lexxy-editor>.connectedCallback` (src/elements/editor.js:84-...): `this.config = new Configuration(this)`, `this.extensions = new Extensions(this)` (L88), then `this.editor = this.#createEditor()` (L90).
- `#createEditor` (editor.js:452-472):
  ```js
  buildEditorFromExtensions({
    name: "lexxy/core", namespace: "Lexxy", theme, nodes: this.#lexicalNodes,
    html: { export: new Map([[TextNode, exportTextNodeDOM], [CodeHighlightNode, exportCodeHighlightNodeDOM]]) },
    $initialEditorState: (editor) => { this.#configureSanitizer(editor); this.#loadInitialValue(editor) },
  }, ...this.extensions.lexicalExtensions)
  ```
  - `#lexicalNodes` (editor.js:481-499): always `CustomActionTextAttachmentNode`; if richText also `QuoteNode, HeadingNode, ListNode, ListItemNode, CodeNode, CodeHighlightNode, LinkNode, AutoLinkNode, HorizontalDividerNode`.
  - Sanitizer is configured inside `$initialEditorState` (after all conversions exist): `EditorSanitizer.register(editor, this.extensions.allowedElements)` (editor.js:848-850). Sanitizer allowlist = every tag in `editor._htmlConversions` (i.e. anything importable) + extension `allowedElements` (src/editor/sanitizer.js:72-79).
  - `html.export` overrides: `src/helpers/text_node_export_helper.js:20-69` (avoid `<b><strong>` doubling, unwrap spans; CodeHighlightNode gets `<a>` wrapper from link state).
- Non-extension registration still done imperatively in `#registerComponents` (editor.js:679-704): `registerRichText` + `registerList` (rich) or `registerPlainText`; table tools, code language picker, attachment toolbar elements appended; markdown shortcuts (`TRANSFORMERS + HORIZONTAL_DIVIDER`) if markdown on.
  - Observation: `HighlightExtension` declares `dependencies: [RichTextExtension]` (highlight_extension.js:33) whose `register` *is* `registerRichText`, while editor.js:685 also calls `registerRichText(this.editor)` → rich-text handlers are registered twice in rich mode. (Only relevant if debugging duplicate command handling.)
- `baseExtensions` (editor.js:217-231), in order: ProvisionalParagraph, CodeHighlighting, Highlight, TrixContent, Tables, RewritableHistory, Attachments, FormatEscape, LinkOpener, PreventLexicalTripleClick, CustomAttachmentDragAndDrop, LineSeparators.
- Toolbar hook: `#attachToolbar` (editor.js:811-820) → `toolbar.setEditor(this)` then `this.extensions.initializeToolbars()`.

### 1.3 `Extensions` collection — src/editor/extensions.js

- Constructor (L5-10) → `#initializeExtensions` (L64-70): `baseExtensions.concat(Lexxy.global.get("extensions"))`, instantiate each `new extension(lexxyElement)`, keep only `.enabled`.
- `lexicalExtensions` (L13-15): `enabledExtensions.map(e => e.lexicalExtension).filter(Boolean)`.
- `allowedElements` (L48-50): flatMap of each extension's `allowedElements`.
- `initializeToolbars()` (L17-24): removes previous `[data-lexxy-extension]` toolbar children, calls each `ext.initializeToolbar(toolbar)`, tags any newly-added direct toolbar children with `data-lexxy-extension` (L36-46), then `toolbar.requestOverflowRefresh()`.
- `dispose()` (L26-30): pops and disposes every extension. Extensions are recreated on every `connectedCallback`.

### 1.4 `LexxyExtension` base — src/extensions/lexxy_extension.js

| member | line | notes |
|---|---|---|
| `constructor(editorElement)` | 6-8 | stores `#editorElement` |
| `editorElement` | 10-12 | the `<lexxy-editor>` |
| `editorConfig` | 14-16 | `editorElement.config` (use `.get("path.to.key")`) |
| `enabled` | 19-21 | default `true` |
| `lexicalExtension` | 23-25 | default `null` (no Lexical extension) |
| `allowedElements` | 27-29 | `[]`; entries: tag string or `{tag, attributes, uriSafeSchemes}` |
| `defineExtension(...)` | 31-33 | re-export of Lexical's so users needn't install `lexical` (avoid dup copies) |
| `initializeToolbar(toolbar)` | 35-36 | hook |
| `setEditorValidity(flags, msg)` | 38-40 | → `editorElement.setElementValidity(this, ...)` (form validity keyed per extension) |
| `dispose()` | 42-43 | hook |

User registration: `Lexxy.configure({ global: { extensions: [MyExt] } })` (config default `extensions: []` at src/config/lexxy.js:3-8). Public exports: `Extension` (src/index.js:17), `Lexical` namespace (index.js:18), `configure` (index.js:16), nodes (src/nodes.js), `REWRITE_HISTORY_COMMAND` (src/commands.js), `EditorSanitizer`, `NativeAdapter`, `highlightCode/highlightElement`. Docs: home/docs/extensions.md (experimental API; lifecycle; `allowedElements`/`uriSafeSchemes` semantics — executable schemes are always stripped L50-60; example L62-114). Test fixtures: test/browser/fixtures/extension-toolbar-button.js, extension-dispose.js.

Note: `lexicalExtension` is a getter evaluated once per editor build; each editor instance gets its own object (fine because each build uses a fresh builder).

### 1.5 Each built-in extension

#### ProvisionalParagraphExtension — src/extensions/provisional_paragraph_extension.js
- enabled: always (no getter). Name `lexxy/provisional-paragraph`, nodes `[ProvisionalParagraphNode]` (L10-13).
- register (L14-22): two `RootNode` transforms — `$insertRequiredProvisionalParagraphs` (L27-42: inserts a `ProvisionalParagraphNode` at start of root if needed and between any two root children where `neededBetween` is true; if selection was at root offset after that node, `selectNext()`), `$removeUnneededProvisionalParagraphs` (L51-55); plus `SELECTION_CHANGE_COMMAND` @HIGH `$markAllProvisionalParagraphsDirty` (L57-64) which adds `HISTORY_MERGE_TAG` so visibility toggles aren't undo steps.
- Works around: Lexical can't place a caret between two non-text-insertable blocks (decorators, tables) or before the first/after the last such block. Provisional paragraphs are invisible caret targets that become real paragraphs when typed into and are never exported.

#### CodeHighlightingExtension — src/extensions/code_highlighting_extension.js
- enabled: `supportsRichText` (L13-15). Name `lexxy/code-highlighting`.
- register: `registerCodeHighlighting(editor, buildMarkupPreservingTokenizer(editor))` (L20-22).
- Why an extension (comment L7-11): transforms must exist before the initial state is applied, otherwise code blocks from the initial value never get tokenized.
- Tokenizer wrapper (L34-47): wraps `PrismTokenizer`; `$tokenize` recovers link ranges (`$extractLinkRangesFromCodeNode`, helpers/code_link_helper.js) and highlight ranges (`$takeHighlightRanges` from highlight_extension) and reapplies them to fresh tokens, because Lexical's retokenizer replaces children with unstyled `CodeHighlightNode`s (drops colors/links).

#### HighlightExtension — src/extensions/highlight_extension.js (475 lines)
- Commands exported: `TOGGLE_HIGHLIGHT_COMMAND`, `REMOVE_HIGHLIGHT_COMMAND`, `BLANK_STYLES` (L12-14). (Toolbar actually dispatches the *string* commands `"toggleHighlight"`/`"removeHighlight"` handled by the command dispatcher.)
- enabled: `supportsRichText` (L27-29). Definition L32-61: `dependencies: [RichTextExtension]`, name `lexxy/highlight`, default `config` (vestigial shape `{color:{...}, "background-color":{...}}`), `html.import: { mark: $markConversion }`. Returns **a configExtension tuple** `[extension, this.editorConfig.get("highlight")]` (L63) so the editor's `highlight` preset (`{buttons:{color,"background-color"}, permit:{...}}`, src/config/lexxy.js:21-50) is shallow-merged in.
- register (L44-60): builds `StyleCanonicalizer`s from button values + `permit` (L292-301); `$registerPreConversion` pushes a `<pre>` converter straight into `editor._htmlConversions` (L92-101) because `html.import` is `Object.assign`-merged and TrixContentExtension also defines `pre`; commands TOGGLE/REMOVE @NORMAL; transforms: `TextNode → $syncHighlightWithStyle` (keeps `highlight` format bit in sync with color/background style, L436-440), `CodeHighlightNode → $syncHighlightWithCodeHighlightNode` (L442-452, sets bit directly since CodeHighlightNode's setFormat is a no-op, `$setCodeHighlightFormat` L421-430 uses `1<<7`), `TextNode → $canonicalizePastedStyles` (L454-467; only for nodes flagged via NodeState `hasPastedStyles` created at L16-18 and set in `$applyHighlightStyle` when `PASTE_TAG`).
- `$applyHighlightStyle(textNode, element)` (L67-79): exported; appends element color/background-color to node style. Used by `mark` import and Trix conversions.
- Pre/code highlights: `$preConversionWithHighlightsFactory` (L107-122) walks `<pre>` DOM for `<mark>` ranges (`extractHighlightRanges` L126-163), stashes them in per-editor `WeakMap pendingCodeHighlights` (L24) keyed by CodeNode key; `$takeHighlightRanges` (L185-201) consumed by the tokenizer; `$applyHighlightRangesToTokens`/`$splitTokenAtHighlightBoundaries` (L203-243).
- `$toggleSelectionStyles` (L303-318): toggle-or-replace per property; inside code blocks uses `$patchCodeHighlightStyles` (L333-368) with a nested `editor.update(..., {skipTransforms:true, discrete:true})` so the retokenizer doesn't rebuild mid-toggle; else `$patchStyleText`.
- Workarounds: Lexical #8013 (backward selection style value), retokenizer dropping styles, CodeHighlightNode format no-op.

#### TrixContentExtension — src/extensions/trix_content_extension.js
- enabled: `supportsRichText`. Name `lexxy/trix-content`. Only `html.import` (L18-41), all priority 1:
  - `em`, `span`, `strong` → only when element has inline `color`/`background-color` (`onlyStyledElements` L46-49); converts via `extendTextNodeConversion("i"|"mark"|"b", $applyHighlightStyle)`.
  - `del` → strikethrough + highlight (L32-35, `$applyStrikethrough` L51-54).
  - `pre[language]` (Trix's attribute) → `extendConversion(CodeNode, "pre", $applyLanguage)` using `normalizeCodeLang` (L36-39, L56-63).
- Helpers `extendConversion` / `extendTextNodeConversion`: src/helpers/lexical_helper.js:99-128 (delegate to a built-in node's importDOM converter for another tag name and post-process).
- Purpose: import legacy Trix HTML (Action Text's previous editor) including its colored spans and `<pre language="">`.

#### TablesExtension — src/extensions/tables_extension.js
- enabled: `supportsRichText`; `allowedElements: ["figure","tbody"]` (L27-29). Name `lexxy/tables`.
- nodes (L34-43): `WrappedTableNode`, `{replace: TableNode, with: () => new WrappedTableNode(), withKlass: WrappedTableNode}`, `TableCellNode`, `TableRowNode`.
- register (L44-132): `setScrollableTablesActive(editor, true)`; `registerTablePlugin(editor)`; root listener → `registerTableSelectionObserver(editor, true)` only once a root exists (Lexxy registers extensions before `setRootElement`); transform clearing every cell's background color (theme adoption + Lexical #8089 hardcoded header bg); transform fixing header states (Lexical #8090: recomputes ROW/COLUMN bits from whether the whole row/column is headers); string commands `insertTableRowAfter/Before`, `insertTableColumnAfter/Before`, `deleteTableRow`, `deleteTableColumn`, `deleteTable` @NORMAL (called from TableController).

#### RewritableHistoryExtension — src/extensions/rewritable_history_extension.js
- Always enabled. `REWRITE_HISTORY_COMMAND` exported (L10) — payload `Record<nodeKey, {patch?, replace?}>`.
- Definition (L15-30): `dependencies: [HistoryExtension]` (this is where undo/redo is provided at all — editor.js never calls `registerHistory`); in `register` grabs `state.getDependency(HistoryExtension).output.historyState.value` (L20-21); registers command @EDITOR.
- `#rewriteHistory` (L42-47): (1) applies patch/replace to current state with a discrete update tagged `HISTORY_MERGE_TAG, SKIP_SCROLL_INTO_VIEW_TAG` (+ `SKIP_DOM_SELECTION_TAG` if unfocused) (L49-59, L86-90); (2) walks every undo/current/redo entry that contains the key and swaps the node in a cloned `_nodeMap` (L61-80, `safeCloneEditorState` L119-123 copies the Map since `EditorState#clone` shares it; bypasses DEV freezing).
- Purpose: async side-effects (upload progress, upload→attachment replacement, image dimensions, preview readiness) must not create undo steps, and undo must not resurrect a stale upload node. Used by `ActionTextAttachmentNode.patchAndRewriteHistory/replaceAndRewriteHistory` (action_text_attachment_node.js:248-258).
- Exposes `historyState` getter (L32-34).

#### AttachmentsExtension — src/extensions/attachments_extension.js
- enabled: `editorElement.supportsAttachments` (config `attachments`) (L23-25). `allowedElements`: `{tag: ActionTextAttachmentNode.TAG_NAME, attributes: ATTACHMENT_ATTRIBUTES}` (L15-16, L27-29) — alt, caption, content, content-type, data-direct-upload-id, data-sgid, filename, filesize, height, presentation, previewable, sgid, url, width.
- Definition (L31-57): name `lexxy/action-text-attachments`; nodes `ActionTextAttachmentNode, ActionTextAttachmentUploadNode, ImageGalleryNode`; register:
  - helper objects (src/editor/attachments/*): `AttachmentDragAndDrop` (drag/drop reorder, gallery join, list drop; DRAGSTART/DROP @HIGH), `AttachmentKeyboardMove` (Alt+Shift+arrows, KEY_DOWN @HIGH), `AttachmentFakeSelection`, `CustomAttachmentLabels` (a11y labels on custom attachments).
  - `registerNodeTransform(ActionTextAttachmentNode, $extractAttachmentFromParagraph)` (L84-101): Lexical wraps decorators found in `<div>` into a paragraph; unwrap/split so attachments are root-level blocks.
  - `DELETE_CHARACTER_COMMAND` @NORMAL `$collapseIntoGallery` (L103-149): Backspace/Delete at gallery edges merges adjacent images into the gallery, collapses empty paragraph between gallery + image, and `$moveSelectionBeforeGallery` (L162-176) prevents Lexical merging gallery into a `<p>`.
  - `KEY_TAB_COMMAND` @HIGH `$focusCaptionFromSelectedAttachment` (L151-159) → `node.focusCaption()`.
  - mutation listener on `ActionTextAttachmentUploadNode` (L59-73): counts live uploads; on `destroyed` aborts the XHR (`editorElement.uploadRequests.abort(key)`); sets custom form validity "Please wait for all files to upload" while uploads > 0 (L75-81).

#### FormatEscapeExtension — src/extensions/format_escape_extension.js
- enabled: `supportsRichText`; `allowedElements`: `ol[start]`, `li[value]` (L17-19).
- nodes (L24-29): replaces `CodeNode` → `EarlyEscapeCodeNode` (preserving language) and `ListItemNode` → `EarlyEscapeListItemNode`.
- register: `INSERT_PARAGRAPH_COMMAND` @HIGH `$escapeFromBlockquote` (L49-97: Enter at start of first non-blank paragraph in a quote inserts a paragraph before the quote; Enter in a blank paragraph inside quote exits — splitting the quote if content follows); `KEY_ARROW_DOWN_COMMAND` @NORMAL `$handleArrowDownInCodeBlock` (L99-115: ArrowDown on last line of a trailing code block creates a paragraph after it); `QuoteNode` transform `$ensureQuoteHasParagraphChild` (L117-122).
- Purpose: "early escape" from blocks with a single Enter on an empty line (Lexical requires more) — see nodes.

#### LinkOpenerExtension — src/extensions/link_opener_extension.js
- enabled: `supportsRichText`. register (L16-23): `CLICK_COMMAND` @NORMAL — Cmd(mac)/Ctrl+click opens link in new tab via `window.open(url,"_blank","noopener,noreferrer")` after `linkNode.sanitizeUrl` (L59-69); `auxclick` middle-click; window keydown/keyup toggles `data-links-openable` attribute on `<lexxy-editor>` (CSS shows pointer: lexxy-editor.css:76); window `focus` → after 200ms re-sync on next mousemove (Chrome drops modifier state after tab switch, L44-48).

#### PreventLexicalTripleClickExtension — src/extensions/prevent_lexical_triple_click_extension.js
- Always enabled. Root listener adds capture-phase `click` on root that `stopPropagation()` when `event.detail === 3` (L22-34), suppressing Lexical's naive triple-click selection fix (facebook/lexical#4512) that breaks real-world selection.

#### CustomAttachmentDragAndDropExtension — src/extensions/custom_attachment_drag_and_drop_extension.js
- enabled: `supportsRichText`. Wraps `CustomAttachmentDragAndDrop` (src/editor/attachments/custom/drag_and_drop.js — DRAGSTART/DROP @HIGH, dragover/dragend on root, drop caret indicator) so inline custom attachments (mentions) can be dragged to a caret position.

#### LineSeparatorsExtension — src/extensions/line_separators_extension.js
- Always enabled; uses `this.defineExtension` (L12). `TextNode` transform replacing first `\r\n|\n|\r|U+2028|U+2029` with `LineBreakNode` per pass (Lexical reruns while dirty) (L4, L23-35). Purpose: macOS text replacements deliver U+2028; literal separators render oddly and don't survive HTML serialization.

---------------------------------------------------------------------------------------------------

## 2. Custom nodes (src/nodes/*.js)

Exports: src/nodes.js re-exports ActionTextAttachmentNode, ActionTextAttachmentUploadNode, CustomActionTextAttachmentNode, HorizontalDividerNode (with `$create…`/`$is…` helpers). Registration location:
- core (`#lexicalNodes`, editor.js:481-499): CustomActionTextAttachmentNode (always), HorizontalDividerNode (rich)
- AttachmentsExtension: ActionTextAttachmentNode, ActionTextAttachmentUploadNode, ImageGalleryNode
- FormatEscapeExtension: EarlyEscapeCodeNode (replaces CodeNode), EarlyEscapeListItemNode (replaces ListItemNode)
- TablesExtension: WrappedTableNode (replaces TableNode)
- ProvisionalParagraphExtension: ProvisionalParagraphNode

Attachment tag name is global config `attachmentTagName` (default `action-text-attachment`, src/config/lexxy.js:4) via `static get TAG_NAME()`.

### ActionTextAttachmentNode — action_text_attachment_node.js (DecoratorNode)
- type `action_text_attachment` (L14-16); `clone` spreads node props (L18-20); `importJSON` (L22-24).
- `importDOM` (L26-81), all priority 1:
  - `<action-text-attachment>` → props from attrs `sgid, url→src, previewable, alt→altText, caption, content-type, filename, filesize, width, height`.
  - `<img>` → `{src, fileName (from URL), altText, contentType:"image/*", width, height}`.
  - `<video>` → src from attr or `<source>`, contentType from source `content-type` or `video/*`.
- constructor (L87-106): `sgid, src, previewSrc, previewable (parseBoolean), previewStatusUrl, pendingPreview, altText, caption, contentType, fileName, fileSize, width, height, uploadError`; captures `this.editor = $getEditor()`.
- `createDOM` (L108-126): error figure / pending-preview figure / previewable image (img in `.attachment__container` + editable caption) / video (file icon + editable caption) / other file (icon + name + size). Figure built by `createAttachmentFigure` (html_helper) with `draggable`, `data-lexical-node-key` (L208-214).
- `updateDOM` (L128-146): recreate only if `uploadError` changed; otherwise patch alt/caption in place.
- `isInline()` (L156-158): inline iff attached and parent isn't the root/shadow root (e.g. inside list item/paragraph).
- `getTextContent` → `"[caption|fileName]\n\n"` (L152-154). `label` (L228-234) for a11y.
- `exportDOM` (L160-176): `<action-text-attachment sgid previewable url alt caption content-type filename filesize width height presentation="gallery">`.
- `exportJSON` (L178-195). `decorate()` returns null (vanilla DOM, not React).
- Preview machinery: `previewSrc` (local blob URL) preloaded then swapped to server `src`, with `patchAndRewriteHistory({previewSrc:null})` and blob revoke (L277-302); non-image previewable (PDF/video) with `pendingPreview` polls `previewStatusUrl` (2xx = processing, anything else = ready; `redirect:"manual"`; backoff 2000*1.5^n up to 120s, 20 attempts, initial 3s delay) or preloads image once (L317-390).
- `focusCaption()` → `lexxy-editor.captionEditor.open(key)` (L236-238); caption click handler (L430-441).

### ActionTextAttachmentUploadNode — action_text_attachment_upload_node.js (extends ActionTextAttachmentNode)
- type `action_text_attachment_upload`; `importDOM` returns null (transient) (L20-23); `exportDOM → {element:null}` (L83-85) so in-flight uploads never serialize.
- Extra props: `file, uploadUrl, blobUrlTemplate, progress, width, height, uploadError` (L25-36).
- `createDOM` (L38-65) starts upload once (side effect guarded by `progress !== null`, L149-176); image preview only if local File + uploadUrl; `<progress>` bar.
- Upload: dynamic `import("@rails/activestorage")` → `DirectUpload`; delegate sets `withCredentials` when global `authenticatedUploads` (L178-194); tracks XHR in `editorElement.uploadRequests` for abort; dispatches `lexxy:upload-start|progress|end` events on the figure (L161-170, L246-249); progress via `patchAndRewriteHistory({progress})`.
- On success `$showUploadedAttachment(blob)` (L232-239) → `AttachmentNodeConversion` (L252-290) builds ActionTextAttachmentNode `{sgid: blob.attachable_sgid, contentType, fileName, fileSize, previewable, previewStatusUrl, src (blob.url if previewable else blobUrlTemplate with :signed_id/:filename), previewSrc (object URL), pendingPreview}` and `replaceAndRewriteHistory`. Bridge-managed uploads (`uploadUrl` null; NativeAdapter) skip DirectUpload.

### CustomActionTextAttachmentNode — custom_action_text_attachment_node.js (DecoratorNode, inline)
- For SGID "content" attachments (mentions, embeds). type `custom_action_text_attachment`.
- `importDOM` (L21-57): matches the attachment tag **only if it has a `content` attribute**, priority 2 (beats ActionTextAttachmentNode's priority 1). Preserves a leading/trailing space as TextNodes (Lexical strips them). Props: `sgid`, `innerHtml` (= `parseAttachmentContent(content)`), `plainText` (textContent or extracted), `contentType`.
- constructor default contentType `application/vnd.<attachmentContentTypeNamespace>.unknown` (L63-72).
- `createDOM(_config, editor)` (L74-99): `<action-text-attachment content-type data-lexxy-decorator draggable data-lexical-node-key>` with innerHtml sanitized by `EditorSanitizer.for(editor).sanitize(html, {safeForXml:true})` (mXSS-safe); a11y tagging of label image/mirrors (L164-211), `exposeLabel/restoreLabel` (L101-121, used by CustomAttachmentLabels).
- `getTextContent` → `"﻿"` (L127-129); `getReadableTextContent` → plainText (used by toString). `isInline()` true. `updateDOM` false.
- `exportDOM` → `<action-text-attachment sgid content="innerHtml" content-type>` (L139-147). Created by `<lexxy-prompt>` (prompt.js:538-540).

### ImageGalleryNode — image_gallery_node.js (ElementNode)
- `$config` type `image_gallery`, extends ElementNode (L8-12); static `transform()` (L14-20): `unwrapEmptyNode || replaceWithSingularChild || splitAroundInvalidChild` (empty → paragraph; 1 child → the child; non-image child → split gallery around it).
- `importDOM` (L22-37): `<div>` whose children are all attachment tags (tags = keys of ActionTextAttachmentNode.importDOM: attachment tag/img/video) and no text → gallery, priority 2.
- `isValidChild` = ActionTextAttachmentNode with previewable image (L43-45). `canBeEmpty` true (to satisfy `$isBlock`) (L69-73); `collapseAtStart` true; `insertNewAfter` (L79-94) special-cases Enter before last image.
- DOM/export: `<div class="attachment-gallery attachment-gallery--N">` (L58-67, L101-105).
- `collapseWith(node, backwards)` (L107-119); `$findOrCreateGalleryForImage` (L172-177).

### HorizontalDividerNode — horizontal_divider_node.js (DecoratorNode, block)
- type `horizontal_divider`; importDOM `<hr>` priority 1 (L17-28); createDOM `<figure class="horizontal-divider" role="presentation"><hr></figure>` (L35-41); exportDOM `<hr>`; getTextContent `"┄\n\n"`; `label` "Horizontal divider". Markdown transformer `HORIZONTAL_DIVIDER` added in editor.js:694.

### ProvisionalParagraphNode — provisional_paragraph_node.js (extends ParagraphNode)
- `$config` type `"provisonal_paragraph"` (sic, typo) with `importDOM: () => null` and `$transform` = `concretizeIfEdited` + `removeUnlessRequired` (L4-13).
- `neededBetween(before, after)` (L15-18): true unless neighbor is an ElementNode that can accept text insertion on that side (`canInsertTextBefore/After`, L101-102). Decorators, tables (WrappedTableNode returns false), document edges qualify.
- DOM class `provisional-paragraph` + `hidden` unless selected (L20-32; CSS lexxy-editor.css:25-35). Overridden `isSelected` (L46-69) treats collapsed element-selection on the parent at index or index+1 as selected.
- `getTextContent` "" and `exportDOM → null` (never serialized). `concretizeIfEdited` replaces itself with a real ParagraphNode once it has text (L75-79).

### EarlyEscapeCodeNode — early_escape_code_node.js (extends CodeNode)
- `$config` type `early_escape_code`. `insertNewAfter` (L12-24): on paste or non-collapsed → super; caret at start → insert paragraph before; caret on whitespace-only last line → newline without indentation carry; empty last line → trim trailing blanks and escape into a new paragraph after; else super. `$fromSelection` static (L6-10).

### EarlyEscapeListItemNode — early_escape_list_item_node.js (extends ListItemNode)
- `$config` type `early_escape_listitem`. In a list inside a blockquote, Enter on a blank item escapes the list (splitting the quote if non-empty items follow) (L12-73); skipped on paste.

### WrappedTableNode — wrapped_table_node.js (extends TableNode)
- `$config` type `wrapped_table_node`; importDOM delegates to TableNode (`<table>`); `canInsertTextBefore/After` false (drives provisional paragraphs); `exportDOM` post-processes `after` to wrap in `<figure class="lexxy-content__table-wrapper">` (L20-34).

JSON type names differ from stock (e.g. `early_escape_code` not `code`), HTML is unchanged. Replacement nodes are registered with `{replace, with, withKlass}` so `$createCodeNode()`, markdown transformers, etc. yield the Lexxy subclass.

---------------------------------------------------------------------------------------------------

## 3. UI elements (src/elements)

Custom-element registration: src/elements/index.js:13-35, called via `setTimeout(defineElements, 0)` in src/index.js:21 (so `Lexxy.configure` in the same tick runs first). Order: toolbar + dropdowns before `lexxy-editor`; `lexxy-prompt`, `lexxy-code-language-picker`, `lexxy-live-region`, `lexxy-attachment-toolbar`, `lexxy-table-tools` after.

### `<lexxy-toolbar>` — src/elements/toolbar.js (`LexicalToolbarElement`)
- ElementInternals role toolbar (L20-26). Found/created by editor: config `toolbar` string = external toolbar element id; else child `lexxy-toolbar` or default created with `defaultTemplate` (editor.js:822-841); hidden when `!richText || toolbar === false`. `toolbar.configure(obj)` sets `data-<key>` attrs (e.g. `data-upload="image|file|both"`, `data-attachments`) driving CSS (lexxy-editor.css:456-467).
- `setEditor(editorElement)` (L65-80): binds click delegation, hotkeys, tabindex reset, selection monitor, history monitor, overflow refresh, focus listeners; resolves `editorPromise` (dropdowns await it via `getEditorElement()`), sets `connected` attr. `connected` attribute change → reconnect (L51-55).
- Buttons: any `[data-command]` click → `editor.update(() => editor.dispatchCommand(command, payload))`; keyboard activation not inside a dropdown uses `SKIP_DOM_SELECTION_TAG` and keeps focus in toolbar; otherwise refocuses editor (L126-148). `aria-disabled="true"` buttons ignored. String commands resolved by src/editor/command_dispatcher.js (COMMANDS list L30-56, handler `dispatch<Capitalized>` registered at priority 0, L308-313).
- Hotkeys (L154-180): keydown on `<lexxy-editor>`; any toolbar element with `data-hotkey="cmd+k ctrl+k"` (space-separated combos, modifiers order ctrl/cmd/alt/shift + key) is `.click()`ed. Default template only uses it for the link button (L438). Bold/italic/underline/undo come from Lexical rich-text/history key handling (docs home/docs/hotkeys.md).
- State sync (L209-256): `registerUpdateListener` → `#updateButtonStates` reads `this.selection.getFormat()` (Selection controller) and sets `aria-pressed` on bold/italic/strikethrough/underline/format(heading)/lists/unordered-list/ordered-list/highlight/link/quote/code/table, `aria-checked` on paragraph, heading dropdown `updateActiveHeading(tag)`; also closes open dropdowns on every update. Only for RangeSelection with attached anchor. Undo/redo `aria-disabled` via `CAN_UNDO_COMMAND`/`CAN_REDO_COMMAND` @LOW (L218-223).
- Roving tabindex (L182-207): toolbar buttons tabindex -1; on `lexxy:focus` first visible button gets 0; arrows/Home/End via `handleRollingTabIndex` (helpers/accessibility_helper.js).
- Overflow (L86-93, L273-345): `requestOverflowRefresh()` rAF-coalesced; ResizeObserver on toolbar (L116-120). `#refreshOverflow`: move previously overflowed items back by `data-position`, reindex, if `scrollWidth > clientWidth` pop buttons from the end of `:scope > button:not([data-prevent-overflow])` into the overflow dropdown panel (`.lexxy-editor__toolbar-overflow > [data-dropdown-panel]`) as `role=menuitem` until width reclaimed; sets `overflowing` attr; CSP nonce on overflow button. Only direct-child `<button>`s overflow (dropdown elements don't). Image button has `data-prevent-overflow`.
- Default template (L381-488): image (`uploadImage`), file (`uploadFile`), bold, italic, strikethrough, underline, format dropdown (Normal / heading options / Clear formatting), highlight dropdown, link dropdown (`cmd+k ctrl+k`), quote, code, bullet list, numbered list, table (`insertTable`), divider (`insertHorizontalDivider`), undo, redo (push-right), overflow dropdown.
- `dispose()` (L38-49) called by editor disposables on disconnect.

### `<lexxy-toolbar-dropdown>` — src/elements/toolbar_dropdown.js (base class)
- Structure: `:scope > [data-dropdown-trigger]` + `:scope > [data-dropdown-panel]` (hidden attr). Host = closest `lexxy-toolbar, lexxy-table-tools` (L32-34). Waits for host's editor (L94-99) then `editorReady()`. Hooks `editorReady/onOpen/onClose`.
- open: `aria-expanded`, unhide, focus first button/input with `focusVisible` (L56-62, L118-130); close: optionally focus editor. Trigger click toggles; closes siblings via `host.closeDropdowns({except})`. Escape closes and returns focus to trigger if opened by keyboard from the host (L101-112); dialog panels trap Tab (`trapFocusAtTabBoundary`); menu panels get arrow navigation with wrap.
- Subclasses: `HighlightDropdown` (dropdown/highlight.js) builds color buttons from config `highlight.buttons` (`--max-colors` CSS var), `menuitemcheckbox`; click dispatches `"toggleHighlight"` `{[style]: value}`; onOpen reads `$getSelectionStyleValueForProperty` with Symbol default (Lexical #8013) to set `aria-checked` and disable "Remove all coloring". `LinkDropdown` (dropdown/link.js): URL input (`required` while open), Enter/Link → `"link"` command, Unlink → `"unlink"`; prefills from `selection.nearestNodeOfType(LinkNode)`.
- `<lexxy-heading-dropdown>` (dropdown/heading.js — plain HTMLElement, `display: contents`) populates `.lexxy-heading-options` from config `headings` (default h2/h3/h4); first 3 get presets Large/Medium/Small with commands `setFormatHeadingLarge|Medium|Small`, further ones `applyHeadingFormat` with tag payload; `menuitemradio` + `aria-checked` via `updateActiveHeading`.
- toolbar_icons.js: inline SVG strings keyed bold, italic, strikethrough, underline, heading, h1-h6, paragraph, clearFormatting, highlight, link, quote, code, ul, ol, image, attachment, table, hr, undo, redo, overflow.

### `<lexxy-table-tools>` + TableController — src/elements/table/*
- Appended into editor by `#registerTableComponents` (editor.js:706-711). `lexxy-floating-controls`, role toolbar. Buttons: row group (− / "N rows" more-menu / +), column group, "Delete this table?" (table_tools.js:67-181). More-menu is a `lexxy-toolbar-dropdown` with Add before/after, Toggle style (header), Remove.
- Update listener → `tableController.updateSelectedTable()`; shows/positions over table (top, horizontal center) and updates row/column counts via `$getElementForTableNode` (L262-335). Hover/focus highlights affected cells with theme `tableCellHighlight` + data-action attrs for CSS preview (L223-260). Alt+F10 (KEY_DOWN @HIGH) focuses tools; Escape returns to cell.
- TableController (table_controller.js): command names built as `${action}Table${ChildType}${Direction}` (L195-201) → handled by TablesExtension commands; toggle header via `setHeaderStyles` XOR (L150-177); after structural command, selects next best cell on next frame (L208-242). Key handlers @HIGH (L325-367): Backspace in empty first cell of empty row deletes row; in empty non-first cell moves to previous cell; Enter (no modifiers, not in list/code) moves to same column next row, in last row inserts row (or if last row empty, deletes it and continues after table).
- table_icons.js keys: insert-row-before/after, delete-row, toggle-row, insert-column-before/after, delete-column, toggle-column, delete-table.

### `<lexxy-attachment-toolbar>` — src/elements/attachment_toolbar.js
- Appended when attachments enabled (editor.js:721-726). Floating controls with "ALT" (alternative text dialog, `AlternativeTextDialog`) and Remove buttons (L56-109). Shown via `registerLabelledDecoratorSelection(editor, cb)` (lexical_helper) when a labelled decorator is selected (L138-157). Positions through CSS vars `--lexxy-anchor-top/left/width/height` relative to editor padding box, flips with `data-overflow` (L217-238); ResizeObserver + capture scroll listener; MutationObserver on figure class to refresh `data-presentation` (gallery|inline|preview|block), `data-node-type`, `data-content-type` (L159-215). ALT hidden unless `action_text_attachment` previewable and editor `data-action-text-supports-alt != "false"`. Alt+F10 focuses toolbar; Escape returns & re-selects node (L111-130, L255-271).

### `<lexxy-code-language-picker>` — src/elements/code_language_picker.js
- Appended in rich mode (editor.js:713-718). `<select>` (or user-provided child select) of languages = Lexical `CODE_LANGUAGE_FRIENDLY_NAME_MAP` + ruby/php/go/bash/json/diff/kotlin, "Plain text" first (L64-81). Update listener shows/positions it at code block's top-right when selection is in a CodeNode (L108-152); change → `codeNode.setLanguage`. mousedown dispatches cancellable `lexxy:code-language-picker-open` {languages, currentLanguage} for native bridges (L83-96).

### `<lexxy-live-region>` — src/elements/live_region.js
- `aria-live=assertive` span; `announce(msg)` appends a div removed after 1s (L1-36). Used for a11y announcements.

### `<lexxy-prompt>` — src/elements/prompt.js (`LexicalPromptElement`)
Attributes: `trigger` (string, e.g. `@`, `#`, `person:`), `name` (used in default content type `application/vnd.<namespace>.<name>`, L533-536), `src` (remote), `remote-filtering`, `supports-space-in-searches`, `only-at` (regex of what must precede trigger; default `^|[ \n]`, L17, L130-132), `vertical-direction` (`top|bottom`), `empty-results` (message; default "Nothing found"), `insert-editable-text`.
- Source selection (L85-96): `src` + `remote-filtering` → `RemoteFilterSource` (src/editor/prompt/remote_filter_source.js: fetch `src?filter=<term>` per keystroke, `debounceAsync` 200ms, max 100); `src` alone → `DeferredPromptSource` (fetch once at connect, filter locally); else `InlinePromptSource` (child `<lexxy-prompt-item>`s). Local filtering (local_filter_source.js:84-110): `filterMatchPosition` (string_helper.js:19-27: lowercase + strip diacritics, match at a word boundary `(?<![\p{L}\p{N}])`), sorted by match position, capped at 100. Remote responses are HTML containing `<lexxy-prompt-item>`s (base_source.js:25-34). List items `<li role=option class=lexxy-prompt-menu__item>` from `template[type=menu]` (base_source.js:16-23).
- Enabled only if `#promptContentTypePermitted` (L134-149): `insert-editable-text` always; else requires attachments enabled and at least one editor template's `content-type` (or default) permitted by `permittedAttachmentTypes`.
- Trigger detection (L98-128): update listener; not in code block; text before caret ends with trigger and text before trigger matches only-at regex → dispose listeners and `#showPopover`.
- `#showPopover` (L205-224): `showPopoverId` counter guards races across async (build/filter); builds `<ul role=listbox class=lexxy-prompt-menu>` appended to `<lexxy-editor>` (not native `[popover]` since it needs arbitrary x/y, L550-559); filter; make visible; register keydown (Escape hides; `,` selects then inserts comma) and debounced (50ms) `lexxy:change` refiltering; Lexical commands at CRITICAL: Enter/Tab select, Space select (+ `INPUT_COMMAND` for Android insertText " ") unless `supports-space-in-searches`, ArrowUp/Down move (L226-255). Cursor listener hides when caret leaves the "trigger+term" run (space/newline breaks, L151-191).
- Filtering (L373-411): uses `contents.containsTextBackUntil/textBackUntil(trigger)`; re-checks after await (e.g. markdown `# ` heading shortcut consumed the trigger during a remote fetch), and stale results dropped when `showPopoverId` changed. (`initialPrompt` flag at L374 is never set anywhere — dead.)
- Positioning (L303-340): from `selection.cursorPosition`; CSS vars `--lexxy-prompt-offset-x/y`; `data-anchored` (menu hidden until anchored, lexxy-editor.css:1123), `data-clipped-at-right`, `data-clipped-at-bottom` (flip above when overflowing window or `vertical-direction=top`).
- A11y: sets `aria-controls`, `aria-activedescendant`, `aria-haspopup=listbox` on content element (L269-296).
- Insertion (L484-540): stringToReplace = trigger + term; `insert-editable-text` → nodes from `template[type=editor]` HTML via `editorElement.$generateNodesFromDOM`; otherwise each permitted editor template → `CustomActionTextAttachmentNode({sgid: template sgid || item sgid, contentType, innerHtml})`, separated by " " text nodes; `contents.replaceTextBackUntil(string, nodes)`.
- Turbo: popover removed on `turbo:before-cache` (L361-371). Reconnect on `connected` attr change.

---------------------------------------------------------------------------------------------------

## 4. Styling (app/assets/stylesheets)

- Files: `lexxy.css` (imports content + editor), `lexxy-variables.css` (88 lines, `:root` tokens), `lexxy-content.css` (504 lines, rendered-content styles under `:where(.lexxy-content)`), `lexxy-editor.css` (1318 lines, editor chrome under `:where(lexxy-editor)` etc.). Both content and editor files `@import` variables. All selectors wrapped in `:where()` → zero specificity, easy to override. Uses CSS nesting.
- Variables (lexxy-variables.css): ink scale `--lexxy-color-ink*`, accent scale, red/green/blue/purple, code token colors `--lexxy-color-code-token-*`, semantic aliases (`--lexxy-color-canvas`, `-text`, `-text-subtle`, `-link`, `-selected*`, `-code-bg`, `-floating-controls-separator`), highlight palettes `--highlight-1..9` (text) and `--highlight-bg-1..9` (background) — referenced by default highlight buttons as `var(--highlight-N)` values stored in content, table colors, `--lexxy-font-base/mono`, `--lexxy-text-small`, `--lexxy-content-margin`, focus ring vars, `--lexxy-toolbar-button-size: 2lh`, `--lexxy-radius`, `--lexxy-shadow`, `--lexxy-z-popup`.
- Editor-scoped vars (lexxy-editor.css:3-20): `--lexxy-editor-padding`, `--lexxy-editor-rows` (uses `attr(rows lh, 8lh)` when supported → `rows` attribute sets min height), toolbar gap/spacing/padding/border/height. `container-type: inline-size`.
- No built-in dark theme in variables (only a `prefers-color-scheme: dark` bit for the code language picker at lexxy-editor.css:1074); docs (home/docs/css-setup.md) point to test/dummy/app/assets/stylesheets/sandbox.css for a dark mode example via overriding variables.
- Theme classes (src/config/theme.js) passed to Lexical: text formats `lexxy-content__bold|italic|strikethrough|underline|highlight`; tables `lexxy-content__table-cell--header`, `--selected`, `lexxy-content__table--selection`, `lexxy-content__table-wrapper` (scrollable wrapper), `--highlight`, `--focus`; nested list item `lexxy-nested-listitem`; `codeHighlight` maps Prism token types to 8 classes `code-token__{attr,comment,function,operator,property,punctuation,selector,variable}`.
- Content styles (lexxy-content.css): headings, `.attachment-gallery`, format classes, blockquote, links, code/pre, lists, `hr`/`.horizontal-divider`, Prism `.token.*` (for rendered view via `highlightCode`), tables incl. `:where(.lexxy-content__table-wrapper)` (L255), attachments (`.attachment`, `--preview`, `--file`, per-extension icon colors pptx/js/docx/xlsx, `--error`), custom attachments `action-text-attachment[content-type^="application/vnd.actiontext"]` (L465).
- Editor styles (lexxy-editor.css): provisional paragraph hidden (L25), `.node--selected`, `[data-links-openable] a` (L76), table editing UI, drag/drop indicators `.lexxy-drop-caret`, `.lexxy-drop-target--*` (L257-318), editable caption, `.lexxy-editor--empty` placeholder via `::before` (L390), `.lexxy-editor__content`, `.lexxy-editor--drag-over`, toolbar (L439-531: `[data-attachments=false]`, `[data-upload=…]` hide buttons, `--push-right`), dropdowns (L532-796: panels, overflow menu, link dialog, highlight grid), `.lexxy-floating-controls` (L797: table tools L873, attachment toolbar L979, code language picker L1052), prompt menu (L1085-1170), live region/fake selection visually hidden (L1175), caption editor (L1198), alternative text dialog (~L1230-1318).
- Rendered Action Text content should be wrapped in `<div class="lexxy-content">` via `app/views/layouts/action_text/contents/_content.html.erb` (docs css-setup.md).
- Linting: `@eslint/css` recommended + `css/use-baseline` (2023, warn) for `app/**/*.css` (eslint.config.js:12-20).

---------------------------------------------------------------------------------------------------

## 5. Build & distribution

- `rollup.config.mjs` (gem build, `yarn build`): input `src/index.js` → `app/assets/javascript/lexxy.js` (ESM + sourcemap) and `lexxy.min.js` (terser); gzip + brotli sidecars; bundles all deps (Lexical, DOMPurify, marked, Prism) except external `@rails/activestorage` (host must pin it; dynamic `import()` in upload node). `nodeResolve`, `commonjs`, `inject` Prism global for `prismjs/components/**`. `yarn watch` = `rollup -wc --watch.onEnd="rails restart"` (Procfile.dev `js:` process; `web: bin/rails server`).
- `rollup.config.npm.mjs` (`yarn build:npm`, also `prepare`/`prerelease`): input `{lexxy: src/index.js}` → `dist/lexxy.esm.js`; `manualChunks` forces modules matching `prismjs` or `code_highlighting_helper` into `dist/lexxy_helpers.esm.js` (no hash, `minifyInternalExports:false`); externals: `lexical`, `@lexical/*`, `dompurify`, `marked`, `prismjs(/…)`, `@rails/activestorage` (npm consumers dedupe); copies stylesheets to `dist/stylesheets`. package.json `exports`: `"."` → dist/lexxy.esm.js, `"./helpers"` → dist/lexxy_helpers.esm.js (so `import { highlightCode } from "@37signals/lexxy/helpers"` avoids loading the editor). npm name `@37signals/lexxy`; `@rails/activestorage` optional peer dep.
- `app/assets/javascript/` is gitignored (.gitignore) — gem release packages the built file (gemspec `spec.files = Dir["{app,config,db,lib}/**/*",…]`), and `ext/Rakefile` (gemspec `spec.extensions`) builds on install when missing (git-sourced gem): requires yarn; `yarn install --frozen-lockfile --ignore-scripts` + `yarn build` (skips npm `prepare`).
- Engine (lib/lexxy/engine.rb): adds `app/assets/stylesheets` and `app/javascript` to asset paths (L45-50); importmap usage `pin "lexxy", to: "lexxy.js"` + `pin "@rails/activestorage", to: "activestorage.esm.js"` (home/docs/index.md:26-31). Engine also widens Action Text sanitizer tags/attributes (video/audio/source/embed/table…, style, data-language, value, start; allows CSS `var()`), L52-61.
- ESLint (eslint.config.js): ignores dist, app/assets/javascript, test, lib, bin, config, docs…; `src/**/*.js` rules: double quotes, no semicolons, array-bracket-spacing always, object-curly-spacing always, `func-style: declaration`, camelcase, prefer-const, no-var, `sort-imports` (member sort only), `no-restricted-globals: event`, `compat/compat` (browserslist `baseline 2023, not dead`); same style rules for `scripts/**/*.js` with node globals.
- vitest.config.js: jsdom env, alias `src`, excludes `**/browser/**`.
- bin/: `dev` (kills old server/port 3000, `foreman start -f Procfile.dev -p $PORT`), `setup` (actionlint/shellcheck/zizmor, bundle, yarn, build, playwright browsers, db prepare), `ci` (config/ci.rb: rubocop, yarn lint, actionlint, zizmor, yarn test, rails test:all, playwright chromium), `link-to-local-lexical link|unlink|status` (yalc-based linking of a local Lexical monorepo with yarn resolutions), `rails`, `rubocop`.
- Benchmarks (scripts/benchmarks): `run-browser-benchmarks.js` starts a Vite server on test/browser fixtures, launches Chromium, loads `/benchmarks.html` (fixtures/benchmarks.js exposes `window.lexxyBenchmarks.measureScenario`), scenarios `bootstrap-empty-editor`, `bootstrap-many-editors` (20), `load-large-content`, `load-very-large-table` (120×18), `load-many-attachments` (60); flags `--list-scenarios`, `--scenario a,b`, `--warmup`, `--iterations`, `--headed`, `--port`; output `tmp/browser-benchmarks.json`. `compare-browser-benchmarks.js` flags regression when median delta exceeds both absolute ms and relative thresholds (default 20ms/20%; per-scenario overrides L10-…); CI `.github/workflows/benchmarks.yml`.

---------------------------------------------------------------------------------------------------

## 6. Test suites

- **Vitest** (`yarn test`): `test/javascript/unit/**` (config, editor [sanitizer, headings config, deferred init, permitted attachment types, replace_text_back_until, list item inserter, code block links…], helpers, sanitization DOMPurify tests) and `test/javascript/native/**` (NativeAdapter bridge: adapter registration, attributes change, code language, editor initialized, pending attachment, selection freeze). `test/javascript/unit/helpers/editor_helper.js` registers elements in jsdom with stubs for ElementInternals and ResizeObserver.
- **Playwright** (`yarn test:browser`, config test/browser/playwright.config.js): `webServer` runs `npx vite --config test/browser/vite.config.js` whose root is `test/browser/fixtures` and aliases `lexxy` → `../../src/index.js` — i.e. **the editor is mounted from source with no Rails and no build step**. Fixtures are static HTML pages (index.html: form with `<lexxy-editor class="lexxy-content" placeholder required>` + `editor.js` importing `lexxy` and `events_logger.js`; styles.css imports the three real stylesheets). Many variant fixtures: attachments-*, mentions*.html (inline `<lexxy-prompt>` items), prompt-*.html, single-line, rich-text-disabled, toolbar-disabled/external, extension-toolbar-button(.js), extension-dispose(.js), sanitizer-isolation, benchmarks. Projects chromium/firefox/webkit; retries 2 locally/1 CI; CI workers 1.
  - `test_helper.js` extends `test` with an `editor` fixture = `EditorHandle` (helpers/editor_handle.js: `waitForConnected()` waits for `[connected]` and root mounted on content element, `value()/setValue()/plainTextValue()/isEmpty/isBlank/focus/flush…`). Helpers: assertions.js (`assertEditorHtml`, `assertEditorPlainText`, `assertEditorTableStructure`, console monitoring), active_storage_mock.js (`mockActiveStorageUploads(page, opts)` intercepts direct-upload/blob routes with delays/holds/failures/preview-status), attachment_helpers, gallery_test_helpers, toolbar helpers, html normalize.
  - Test folders (tests/): attachments, editor, formatting, modes, paste, prompts, tables + root code_highlighting/events/trix_html tests (see AGENTS.md table).
- **Capybara system** (`bin/rails test:all`): test/system/*.rb (+ attachments/, trix/), `ApplicationSystemTestCase` uses `selenium_chrome_headless`, `app_host http://lexxy.localhost`, recovers from Chrome crashes. Uses built `app/assets/javascript/lexxy.js` (so run `bin/dev`/rebuild after src changes). Dummy app test/dummy (posts, trix_posts, people, groups, sandbox, demo_contents, authenticated direct uploads controllers); posts form (test/dummy/app/views/posts/_form.html.erb) toggles global config via query params (attachment_tag_name, configure_authenticated_uploads, attachment_content_type_namespace, toolbar_external…). Fixtures: test/fixtures/posts.yml, people.yml, action_text/rich_texts.yml, files/. Other Ruby tests: test/helpers, test/actiontext, test/integration.
