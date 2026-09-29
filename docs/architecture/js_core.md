# Lexxy JS core: detailed notes

Paths are relative to the repo root unless they start with `lexical/…`, which means `lexical@v0.44.0:packages/…` (Lexical v0.44.0).

---

## 0. Package entry points and build

### `src/index.js` (npm and gem entry)
- `:1-2` import side effects: `config/prism` sets `window.Prism.manual = true` before importing Prism and its language components (`src/config/prism.js:1-38`). `config/dom_purify` creates Lexxy's **own** DOMPurify instance and registers its hooks.
- `:4,21` `setTimeout(defineElements, 0)` defers custom-element registration by one task. This lets a host call `Lexxy.configure(...)` synchronously right after import, before any `<lexxy-editor>` upgrades. `home/docs/configuration.md` documents this requirement.
- Public exports:
  - `export * from "./nodes"` → `src/nodes.js`: `ActionTextAttachmentNode` (and `$isActionTextAttachmentNode`), `ActionTextAttachmentUploadNode` (+ `$createActionTextAttachmentUploadNode`), `CustomActionTextAttachmentNode` (+ `$isCustomActionTextAttachmentNode`), `HorizontalDividerNode`.
  - `export * from "./commands"` → `src/commands.js`: only `REWRITE_HISTORY_COMMAND`.
  - `highlightCode`, `highlightElement` from `helpers/code_highlighting_helper` (Prism highlighting for rendered `pre[data-language]`, applied outside the editor).
  - `NativeAdapter` (`editor/adapters/native_adapter.js`).
  - `EditorSanitizer` (`editor/sanitizer.js`), so consumers that register Lexxy nodes in their own Lexical editor can `EditorSanitizer.register(editor, allowlist)`.
  - `configure = Lexxy.configure` (`config/lexxy.js`).
  - `Extension` = `LexxyExtension` base class (`extensions/lexxy_extension.js`).
  - `Lexical` = `export * as Lexical from "lexical"` (the whole lexical namespace, re-exported so extensions share Lexxy's copy).
- `src/elements/index.js` (`defineElements`) registers these custom elements: `lexxy-toolbar`, `lexxy-toolbar-dropdown`, `lexxy-heading-dropdown`, `lexxy-highlight-dropdown`, `lexxy-link-dropdown`, then `lexxy-editor`, then `lexxy-prompt`, `lexxy-code-language-picker`, `lexxy-live-region`, `lexxy-attachment-toolbar`, `lexxy-table-tools`. The toolbar must be defined before the editor, and the prompt after it (see the comments in the file).

### Builds
- `rollup.config.mjs` builds the gem asset: `src/index.js` → `app/assets/javascript/lexxy.js` (with sourcemap), `lexxy.min.js` (terser), plus `.gz` and `.br`. Everything is bundled (Lexical, DOMPurify, marked, Prism) except `@rails/activestorage`, which stays external. The upload node loads it with a dynamic `import("@rails/activestorage")` (`nodes/action_text_attachment_upload_node.js:156`), so the host must provide it (for example with an importmap pin). The `inject` plugin gives Prism language components a global `Prism`.
- `rollup.config.npm.mjs` builds the npm package into `dist/`, ESM only: `lexxy.esm.js`. All `@lexical/*`, `lexical`, `dompurify`, `marked`, `prismjs`, and `@rails/activestorage` are **external** (peer/runtime deps). `manualChunks` pulls `prismjs` and `code_highlighting_helper` into a **`lexxy_helpers.esm.js`** chunk with no hash, and `minifyInternalExports: false` keeps its export names readable. `package.json` `exports`: `"."` → `dist/lexxy.esm.js`, `"./helpers"` → `dist/lexxy_helpers.esm.js`. So `@37signals/lexxy/helpers` gives you `highlightCode`/`highlightElement` (plus Prism) without loading the editor, which suits rendered views. Stylesheets are copied to `dist/stylesheets`.
- Dependencies are pinned to Lexical `^0.44.0`, `dompurify ^3.4.13`, `marked ^16.4.1`, `prismjs ^1.30`. `@rails/activestorage >= 7` is an optional peer.

---

## 1. `<lexxy-editor>` lifecycle (`src/elements/editor.js`, class `LexicalEditorElement`)

### Static and state
- `static formAssociated = true` (`:54`). The element is a **form-associated custom element**: the constructor calls `this.attachInternals()` and sets `internals.role = "presentation"` (`:75-79`). The editable div carries `role="textbox"` instead.
- `static debug = false` (`:55`). When true, `#attachDebugHooks` logs HTML, string, empty, and blank on every update (`:800-809`).
- `static observedAttributes = ["autocapitalize", "connected", "required"]` (`:58`). `attributeChangedCallback` dispatches to `${name}ChangedCallback` (`:136-140`).
- Private fields: `#initialValue`, `#previousInternalFormValue`, dispatch flags, `#listeners` (ListenerBin), `#disposables` (array of objects with `dispose()`), `#historyState {undo, redo}`, `#validity` Map, `#validationTextArea` (a hidden `<textarea>` used only to compute `valueMissing` validity and messages), `#uploadRequests`, `#liveRegion`.

### `connectedCallback` (`:85-123`), in order
1. `this.id ||= generateDomId("lexxy-editor")`.
2. `this.config = new Configuration(this)`. This is the per-element resolved config (see §2).
3. `this.extensions = new Extensions(this)` (`editor/extensions.js`). It instantiates `baseExtensions` plus `Lexxy.global.get("extensions")` and keeps those with `enabled === true`.
4. `this.editor = this.#createEditor()` (`:450-471`):
   - Creates `div.lexxy-editor__content` if needed (`#createEditorContentElement` `:501-520`): `contenteditable`, `role="textbox"`, `aria-multiline` = `supportsMultiLine`, `aria-required`, `aria-invalid=false`, `aria-label` from `internals.labels` text, `placeholder` from the attribute. It copies every `aria-*` attribute from the host, transfers `autocapitalize`, and moves `tabindex` from the host to the content element (removing it from the host, default 0). It is appended to the host.
   - **`buildEditorFromExtensions(...)`** from `@lexical/extension`, not `createEditor`. The root extension object: `name: "lexxy/core"`, `namespace: "Lexxy"`, `theme` (`config/theme.js`), `nodes: this.#lexicalNodes`, `html.export: Map([[TextNode, exportTextNodeDOM], [CodeHighlightNode, exportCodeHighlightNodeDOM]])`, and `$initialEditorState: (editor) => { #configureSanitizer(editor); #loadInitialValue(editor) }`. The remaining arguments are `...this.extensions.lexicalExtensions`.
   - Lexical ref: `lexical/lexical-extension/src/LexicalBuilder.ts:80` (`buildEditorFromExtensions`) and `:404-490` (`buildCreateEditorArgs`, which merges nodes, `html.export` maps, `html.import` via **`Object.assign` per tag**, and themes). With no `onError`, the default rethrows (`defaultOnError`). `$initialEditorState` is applied by `InitialStateExtension` in the **afterRegistration** phase, inside `editor.update(..., {tag: HISTORY_MERGE_TAG})` (`lexical/lexical-extension/src/InitialStateExtension.ts:51-88`). So every extension's `register` (transforms, code highlighting) has already run, and the initial load does not create an undo entry. The returned editor has `dispose()`, which unregisters extensions and calls `setRootElement(null)` (`LexicalBuilder.ts:202-215`).
   - `#lexicalNodes` (`:481-499`) always includes `CustomActionTextAttachmentNode`. When rich text is on, it adds `QuoteNode, HeadingNode, ListNode, ListItemNode, CodeNode, CodeHighlightNode, LinkNode, AutoLinkNode, HorizontalDividerNode`. Extensions contribute more nodes: attachments add `ActionTextAttachmentNode`, `ActionTextAttachmentUploadNode`, `ImageGalleryNode`; tables add `WrappedTableNode` (replacing `TableNode`), `TableCellNode`, `TableRowNode`; format-escape adds `EarlyEscapeCodeNode` (replacing `CodeNode`) and `EarlyEscapeListItemNode` (replacing `ListItemNode`); provisional-paragraph adds `ProvisionalParagraphNode`.
5. `this.contents = new Contents(this)`, `this.selection = new Selection(this)`, `this.clipboard = new Clipboard(this)`. The order matters: Clipboard reads `editorElement.contents`, and CommandDispatcher reads `selection` and `contents`.
6. Live region: reuses a child `lexxy-live-region` or creates one (`:104-106`).
7. `this.adapter = new BrowserAdapter()` (a no-op adapter) and `this.#uploadRequests = new UploadRequests()`.
8. `CommandDispatcher.configureFor(this)`.
9. `#initialize()` (`:425-438`): `#registerComponents` → `#handleEnter` → `#registerFocusEvents` → `#registerHistoryEvents` → `#registerFileAcceptFilter` → `#attachDebugHooks` → `#attachToolbar` → `#resetBeforeTurboCaches` → `#observeAriaAttributes` → `#setInternalFormValue(this.value, {suppressEvent: true})` → `#synchronizeWithChanges`.
10. `this.toggleAttribute("connected", true)`.
11. `requestAnimationFrame` → `#mountRoot()` (`:475-479`) sets `setEditable(false)`, then `setRootElement(content)`, then `setEditable(true)`. Lexical only syncs DOM selection (and focuses the root) when `editor._editable` is true (`lexical/lexical/src/LexicalUpdates.ts:630-640`), and `setRootElement` commits pending updates (`lexical/lexical/src/LexicalEditor.ts:1372-1433`). Keeping the editor non-editable during the mount therefore stops it stealing focus. After mounting it runs `#handleAutofocus()` (focuses only if nothing on the page is focused and this is the first `[autofocus]`), then `#dispatchInitialize()`.
   - **Important:** Lexical has no root element until this rAF. Extensions that need the root use `registerRootListener`. For example, `TablesExtension` wires table selection this way, and a comment explains why.

### `#registerComponents` (`:680-705`): the Lexical "plugins"
- Rich text (`config.richText`):
  - `registerRichText(editor)` and `registerList(editor)`.
  - `#registerTableComponents()` appends or reuses `<lexxy-table-tools>`, `#registerCodeLanguagePicker()` does the same for `<lexxy-code-language-picker>`, and when attachments are on `#registerAttachmentToolbar()` appends `<lexxy-attachment-toolbar>` and creates `this.captionEditor = new CaptionEditor(this)`.
  - When markdown is on: `registerMarkdownShortcuts(editor, [...TRANSFORMERS, HORIZONTAL_DIVIDER])` plus `registerMarkdownLeadingTagHandler(editor, transformers)`.
- Plain text: `registerPlainText(editor)`.
- **History** comes from `RewritableHistoryExtension`, which declares `dependencies: [HistoryExtension]` (`extensions/rewritable_history_extension.js:18`). History is on in every mode.
- **Tables** come from `TablesExtension` → `registerTablePlugin` (+ `setScrollableTablesActive`).
- **Code highlighting** comes from `CodeHighlightingExtension` → `registerCodeHighlighting(editor, markupPreservingTokenizer)`. It is registered through an extension so its transforms exist before `$initialEditorState` runs (see the comment at `code_highlighting_extension.js:7-11`).
- **Links:** `LinkNode` and `AutoLinkNode` are registered, but there is no `LinkExtension`, `registerLink`, or auto-link matcher. Links are created with `$toggleLink`, with `$createAutoLinkNode` (`command_dispatcher.js:103-119`), and by paste (§5).
- Observation: `HighlightExtension` declares `dependencies: [RichTextExtension]` (`extensions/highlight_extension.js:33`), and `RichTextExtension.register = registerRichText` (`lexical/lexical-rich-text/src/index.ts:1147-1153`). `#registerComponents` also calls `registerRichText` directly (`editor.js:685`). In rich-text mode, rich-text command handlers therefore appear to be registered twice. This is mostly harmless because handlers that return `true` stop propagation.

### `#handleEnter` (`:730-751`)
`KEY_ENTER_COMMAND` at NORMAL priority. It swallows Ctrl/Cmd+Enter (preventDefault, return true), which leaves it free for host submit shortcuts. When `!supportsMultiLine` it swallows Enter entirely, which is how single-line mode works.

### Focus and blur (`:753-777`)
`focusin` and `focusout` on the host. `lexxy:focus` fires once when focus enters the editor **or toolbar** (it also calls `#dispatchAttributesChange`). `lexxy:blur` fires when `relatedTarget` is outside both the editor and the toolbar. `currentlyFocused` is tracked.

### `focus()` (`:347-355`)
Does nothing if the contenteditable already contains `document.activeElement`, because `editor.focus()` would commit an update and trigger layout. Otherwise it calls `editor.focus(() => #onFocus())`. `#onFocus` places the cursor at the end when the editor is empty (`selection.placeCursorAtTheEnd()`).

### History (`:793-798`)
`CAN_UNDO_COMMAND` and `CAN_REDO_COMMAND` listeners store `#historyState`, exposed as `canUndo` and `canRedo`.

### Toolbar (`:811-842`)
`#hasToolbar` = `supportsRichText && !!config.get("toolbar")`. `toolbarElement` (`:210-215`) resolves in this order:
- if `toolbar` config is a string, `document.getElementById(id)` (an external toolbar);
- otherwise a child `lexxy-toolbar`;
- otherwise `#createDefaultToolbar()`, which fills `innerHTML = LexicalToolbar.defaultTemplate`, sets `data-attachments`, calls `toolbar.configure(config.toolbar)` (turning each key into a `data-<key>` attribute, for example `data-upload="both"`), and prepends it.

It then calls `toolbar.setEditor(this)` and `extensions.initializeToolbars()`, which calls each extension's `initializeToolbar(toolbar)` and tags added children with `data-lexxy-extension`. If the toolbar has `dispose()`, it is added to the disposables.

### Initial value (`#loadInitialValue` `:593-598`)
`initialHtml = this.valueBeforeDisconnect || this.getAttribute("value") || "<p><br></p>"`. The value comes from the **`value` attribute**, not from a hidden input or textarea. The Rails helper renders `<lexxy-editor name=… value="<html>">` (`lib/lexxy/rich_text_area_tag.rb:3-22`, which also sets `data-direct-upload-url`, `data-blob-url-template`, and `data-action-text-supports-alt`, and pre-renders custom attachments' `content` for attachments without a `url`). The value is stored as `#initialValue`, which is used for form reset.
- `#setEditorHtml(html)` (`:600-605`) calls `$getRoot().clear().selectEnd().insertNodes(#parseHtmlIntoLexicalNodes(html))`.
- `#parseHtmlIntoLexicalNodes` (`:397-404`) turns empty into `<p></p>`, parses with `parseHtml` (DOMParser), runs `this.$generateNodesFromDOM(doc)`, filters out whitespace-only TextNodes and LineBreakNodes (`#isNotWhitespaceOnlyNode` `:409-413`), and wraps bare TextNodes in a paragraph (`#wrapTextNode` `:417-423`).
- `$generateNodesFromDOM(doc, {editor})` (`:275-279`) is the public hook used everywhere, including prompts and contents. It wraps `@lexical/html` `$generateNodesFromDOM`. Under `PASTE_TAG` it converts inline `data:image/...;base64` attachments into upload nodes (`helpers/inline_image_uri_helper.js`). It then drops attachment nodes whose content type is not permitted (`helpers/attachment_filter_helper.js`).
- The initial value is **not sanitized on input**. The `value` getter sanitizes on output, and custom attachment inner HTML is sanitized at `createDOM`.

### Value export (`get value` `:361-363`, `#readSanitizedEditorValue` `:391-395`)
`this.cachedValue ??= editor.read(() => this.sanitizer.sanitize($generateHtmlFromNodes(editor, null)))`. `editor.read` flushes pending updates (`lexical/lexical/src/LexicalEditor.ts:1538-1541`).
- `$generateHtmlFromNodes` (`lexical/lexical-html/src/index.ts:239-254`) walks nodes through `$exportDOM`, which honours `html.export` overrides (`LexicalEditor.ts:807`: `exportDOM: html.export.get(klass)`).
- Custom export functions:
  - `exportTextNodeDOM` (`helpers/text_node_export_helper.js`) avoids Lexical's `<b><strong>` double wrapping: it wraps in `<b>` or `<i>` only if `createDOM` didn't produce `<strong>` or `<em>`, always wraps `<s>` and `<u>`, and unwraps `<span>`s.
  - `exportCodeHighlightNodeDOM` wraps code tokens that carry link state (`code_link_helper` NodeState `codeLink`) in `<a>`.
  - Node `exportDOM` implementations: `ActionTextAttachmentNode.exportDOM` produces `<action-text-attachment sgid previewable url alt caption content-type filename filesize width height presentation="gallery">` (`nodes/action_text_attachment_node.js:160-176`). `CustomActionTextAttachmentNode.exportDOM` produces `<tag sgid content="<innerHtml>" content-type>` (`nodes/custom_action_text_attachment_node.js:139-147`). `ActionTextAttachmentUploadNode.exportDOM` returns `{element: null}`, so in-flight uploads are omitted from the value.
- The cache is cleared on every update (`#clearCachedValues` `:675-678`).

### `set value(html)` (`:365-381`)
`editor.update(..., {discrete: true})`. If the editor has focus it schedules `$onUpdate(() => editor.focus())`, a Safari cursor fix. Otherwise it adds `SKIP_DOM_SELECTION_TAG` so it doesn't steal focus. Then `#setEditorHtml(html)` and `#toggleEmptyStatus()`. Because this is a normal update (not history-merge), it creates an undo entry and fires `lexxy:change` if the HTML differs.

### `toString()` (`:166-170`)
Cached `$getReadableTextContent(root)` (`:1002-1025`). Like `getTextContent`, but `CustomActionTextAttachmentNode.getReadableTextContent()` returns the plain text of mentions, the spacer text node around attachments is skipped (`isAttachmentSpacerTextNode`), and non-inline elements are joined with `"\n\n"`.

### `isEmpty` and `isBlank` (`:281-287`)
- `isEmpty`: `value.trim()` is one of `"<p><br></p>"`, `"<p></p>"`, or `""`.
- `isBlank`: `isEmpty` or `toString()` is whitespace-only.
- The `lexxy-editor--empty` class is toggled on every update and on the setter.

### Form integration
- `#synchronizeWithChanges` (`:619-627`) registers an update listener that clears caches, then `#setInternalFormValue(this.value)` (`internals.setFormValue(html)`; dispatches **`lexxy:change`**, with no detail, only when the HTML differs from the previous value (`:582-591`)), then `#toggleEmptyStatus`, `#requestValidityRefresh` (after `nextFrame`), and `#dispatchAttributesChange`.
- The initial `setFormValue` is suppressed (`:436`), so no change event fires on load.
- Accessors: `form`, `name` (from the attribute), `required`, `validity`, `validationMessage`, `checkValidity()`, `reportValidity()`, and `setCustomValidity(msg)` (routed through the hidden textarea).
- Validity (`:629-673`): `#refreshInternalValidity` sets `textarea.required = required && isBlank` and stores that ValidityState. `setElementValidity(key, flags, message)` lets extensions contribute; for example, `AttachmentsExtension` sets `customError` "Please wait for all files to upload" while uploads are pending. `#calculateValidity` merges all flags and joins messages, then calls `internals.setValidity(validity, message, contentEditable)`. `aria-invalid` is synced only after an `invalid` event (`#validationAttempted`).
- `formResetCallback` (`:159-164`) restores `#initialValue` and dispatches `CLEAR_HISTORY_COMMAND`.
- There is **no `formDisabledCallback`, `formStateRestoreCallback`, `disabled`, or `readonly` support** in `src/`. The only `setEditable` calls are in `#mountRoot`. The docs list `disabled` as a "form attribute", but nothing in the editor implements it. The closest thing is `freezeSelection()`/`thawSelection()` → `adapter.freeze()`, which only `NativeAdapter` implements by setting `contentEditable="false"`.
- ARIA mirroring (`:542-580`): a MutationObserver on host attributes copies `aria-*` changes to the content element and recomputes `aria-multiline` when `single-line` changes. `requiredChangedCallback` syncs `aria-required` and revalidates. `autocapitalizeChangedCallback` retransfers the attribute.

### Modes
- **Plain-text mode:** `rich-text="false"` or preset `richText: false`. It uses `registerPlainText`, has no toolbar (`#hasToolbar` requires rich text), no markdown (`supportsMarkdown = supportsRichText && config.markdown`), and only `CustomActionTextAttachmentNode` among the core nodes. Extensions gated on `supportsRichText`: Highlight, CodeHighlighting, TrixContent, Tables, FormatEscape, LinkOpener, CustomAttachmentDragAndDrop. Always on: ProvisionalParagraph, RewritableHistory, PreventLexicalTripleClick, LineSeparators. Attachments follows its own `attachments` config.
- **Single-line mode:** `multi-line="false"` config, or the deprecated `single-line` attribute (`isSingleLineMode` `:339-341`). `supportsMultiLine = config.multiLine && !single-line`. Enter is swallowed (`:742`), `aria-multiline=false`, and `Contents#appendLineBreakIfNeeded` skips adding line breaks.

### Events dispatched by the editor core
All use `dispatch(el, name, detail, cancelable)` from `helpers/html_helper.js:43-45`: a `CustomEvent`, bubbling, detail defaults to `null`.

| Event | Where | When / detail |
|---|---|---|
| `lexxy:initialize` | `editor.js:904-915` | once per connect, in the rAF after mounting; no detail |
| `lexxy:change` | `editor.js:589` | after any update whose sanitized HTML changed; no detail |
| `lexxy:focus` / `lexxy:blur` | `editor.js:760-773` | focus entering or leaving editor+toolbar |
| `lexxy:file-accept` | `editor.js:261-263` (`acceptsFile`) | **cancelable**, `{file}`. The editor's own listener (`:440-448`) calls `preventDefault` when the content type isn't permitted. Used by `Contents#uploadFiles` and by the data-URI conversion. |
| `lexxy:insert-link` | `clipboard.js:185-195` | pasted a URL; `{url, replaceLinkWith(html, options), insertBelowLink(html, options)}` |
| `lexxy:insert-markdown` | `clipboard.js:204-211` | before inserting pasted markdown; frozen `{markdown, document, addBlockSpacing()}`. Listeners can mutate `document`. |
| `lexxy:upload-start` / `lexxy:upload-progress` / `lexxy:upload-end` | `nodes/action_text_attachment_upload_node.js:161-216` | dispatched **on the attachment `<figure>`** (bubbles): `{file}`, `{file, progress}`, `{file, error}` |
| `lexxy:attributes-change` | `native_adapter.js:25-32` | only with NativeAdapter: `{attributes, link:{href}|null, highlight, headingTag}` |
| `lexxy:editor-initialized` | `native_adapter.js:34-36` | only with NativeAdapter: `{highlightColors:{colors, backgroundColors}, headingFormats:[{label, command, tag}]}` |
| `lexxy:internal:move-to-next-line` | listened to by `selection.js:384` | internal |
| `lexxy:code-language-picker-open` | `elements/code_language_picker.js:84` | UI |

### Adapter API on the element (`:313-336`)
- `registerAdapter(adapter)` replaces the adapter and, if the editor already exists, immediately dispatches editor-initialized and attributes-change.
- `dispatchAttributesChange()` and `dispatchEditorInitialized()` are public wrappers.
- `#dispatchAttributesChange` (`:852-891`) reads the selection (range selections only) and `selection.getFormat()`. It builds a map `{bold, italic, strikethrough, code, highlight, link, quote, heading, unordered-list, ordered-list, undo, redo}` of `{active, enabled}`, plus `linkHref`, `highlight` styles, and `headingTag`, and passes them to `adapter.dispatchAttributesChange`.
- `#resolvedHighlightColors` resolves `var(--highlight-N)` button values to computed colours through the contained `styleResolverRoot()` in a single reflow (`:945-966`).
- `#supportedHeadingFormats` is "Normal" plus configured headings, with labels and commands from `HeadingDropdown`.

### Other public API on the element
- `announce(message)` uses `document.ariaNotify` or the live region.
- `permittedAttachmentTypes` is a frozen array or `null`; config accepts an array or a space-separated string, and `"false"` tokens are filtered out.
- `permitsAttachmentContentType(type)`.
- `directUploadUrl` and `blobUrlTemplate` come from `data-direct-upload-url` and `data-blob-url-template`.
- `supportsAttachments`, `supportsMarkdown`, `supportsMultiLine`, `supportsRichText`, `preset`, `hasOpenPrompt`, `contentTabIndex`, `canUndo`, `canRedo`, `uploadRequests`, `baseExtensions`.

### Disconnect and teardown (`:125-134`, `:968-995`)
- `disconnectedCallback` resets the dispatch flags, saves `valueBeforeDisconnect = this.value` (so moving the element in the DOM keeps its content), clears caches, and calls `#reset()`.
- `#reset()` pops and `dispose()`s every disposable in LIFO order: toolbar, caption editor, attachment toolbar, code picker, table tools, command dispatcher, live region, clipboard, selection, contents, `#listeners` ListenerBin, `editor` (Lexical dispose, which calls `setRootElement(null)`), and extensions. It then resets validity, clears `uploadRequests`, removes the content element, and nulls `this.toolbar`. The comment calls this a prevention for "hangs with Safari when morphing".

### Turbo
- `turbo:before-cache` on `document` calls `#reset()` unless the editor is inside `[data-turbo-permanent]` (`:607-617`).
- The **`connected` attribute** is used for Turbo morphing. The editor sets `connected` on connect. If a morph rewrites attributes (the server HTML lacks `connected`), `connectedChangedCallback` (`:148-152`) sees the change while connected and calls `#reconnect()` in the next rAF: `disconnectedCallback()`, then `valueBeforeDisconnect = null` so the value is reloaded from the new `value` attribute, then `connectedCallback()`.
- The toolbar and prompt elements use the same `connected` pattern.
- The prompt removes its popover on `turbo:before-cache`. `Contents#uploadFiles` guards against a late drop after dispose (`contents.js:286`).

---

## 2. Configuration system

- `src/config/configuration.js`: `Configuration` holds a `#tree` and `merge(...configs)` reduces with `deepMerge` (`helpers/hash_helper.js`, which recurses only into plain objects, so arrays are replaced). `get("a.b.c")` walks keys and throws if an intermediate key is missing.
- `src/config/lexxy.js`:
  - `global` = `Configuration({attachmentTagName: "action-text-attachment", attachmentContentTypeNamespace: "actiontext", authenticatedUploads: false, extensions: []})`.
  - `presets` = `Configuration({default: {attachments: true, markdown: true, multiLine: true, permittedAttachmentTypes: null, richText: true, toolbar: {upload: "both"}, headings: ["h2","h3","h4"], highlight: {buttons: {color: [9 × {value:"var(--highlight-N)", label}], "background-color": [9 × var(--highlight-bg-N)]}, permit: {color: [], "background-color": []}}}})`.
  - `configure({global, ...presets})` merges `global` into global and everything else into presets. That covers overriding `default` and defining named presets.
- `src/editor/configuration.js` (`EditorConfiguration`, per element) is built from `Configuration(presets.default, presets[element.preset], overrides)`.
  - `preset` comes from the `preset` attribute, defaulting to `"default"`.
  - Overrides: for every key of the **default preset**, if the element has the dasherized attribute (`multiLine` → `multi-line`, `richText` → `rich-text`, `permittedAttachmentTypes` → `permitted-attachment-types`), the value is `JSON.parse(attr)` with a fallback to the raw string. So `toolbar="false"` becomes `false`, `headings='["h2"]'` becomes an array, and `toolbar="my-toolbar-id"` stays a string (an external toolbar id).
  - Precedence: attribute > named preset > default. It is resolved once in `connectedCallback`.
- Global options are read directly with `Lexxy.global.get(...)`:
  - `attachmentTagName`: the TAG_NAME of both attachment nodes and the sanitizer's data-URI allowance.
  - `attachmentContentTypeNamespace`: the prompt default content type `application/vnd.<ns>.<promptName>`.
  - `authenticatedUploads`: `withCredentials` on DirectUpload XHRs.
  - `extensions`: extra `LexxyExtension` subclasses appended after `baseExtensions`.
- Extension config: `HighlightExtension.lexicalExtension` returns the tuple `[extension, this.editorConfig.get("highlight")]`, which is Lexical's extension-with-config argument form (`highlight_extension.js:62`).

### `LexxyExtension` base (`extensions/lexxy_extension.js`)
- `constructor(editorElement)`; `editorElement`; `editorConfig` (the element's config); `enabled` (default true); `lexicalExtension` (default null); `allowedElements` (default []; sanitizer allowlist entries, either tag strings or `{tag, attributes, uriSafeSchemes}`); `defineExtension(...)` helper; `initializeToolbar(toolbar)`; `setEditorValidity(flags, message)`; `dispose()`.
- `Extensions` (`editor/extensions.js`): `lexicalExtensions` maps to `.lexicalExtension` and filters out falsy ones; `allowedElements` is the flatMap across extensions; `dispose()` disposes each extension.
- Base extension order (`editor.js:217-232`): ProvisionalParagraph, CodeHighlighting, Highlight, TrixContent, Tables, RewritableHistory, Attachments, FormatEscape, LinkOpener, PreventLexicalTripleClick, CustomAttachmentDragAndDrop, LineSeparators.

---

## 3. Sanitization pipeline

### `src/config/dom_purify.js`
- `DOMPurify = createDOMPurify(window)` (`:88`). Lexxy uses **its own instance**, not the singleton, so it never calls `setConfig` on the host's DOMPurify. The long comment at `:5-56` covers the Trusted Types reasoning:
  - A lazy `trustedTypes.createPolicy("lexxy", …)` is created once and guarded (`:57-86`). `config.TRUSTED_TYPES_POLICY` is always set (to `null` when there is no policy) so DOMPurify doesn't claim the `dompurify` name (`:180-191`).
  - The comment lists unwrapped TT sinks that remain: `parseHtml`, `createElement` content, `highlightElement` innerHTML, and `insertAdjacentHTML` in the custom attachment node.
- `ALLOWED_HTML_ATTRIBUTES = ["alt","class","contenteditable","href","src","style","title"]` (`:93`).
- `DEFAULT_TAG_ATTRIBUTES = {img: ["width","height"]}` (per-tag, and only when `img` is already allowed).
- `ALLOWED_STYLE_PROPERTIES = ["color","background-color"]`.
- Hooks:
  - `uponSanitizeAttribute` / `styleFilterHook` (`:104-123`) keeps only color and background-color in `style` and drops the attribute otherwise.
  - `attachmentUriFilterHook` (from `helpers/sanitization_helper.js`).
  - `stimulusAttributeFilterHook` drops `data-controller` and `data-action`.
  - `uponSanitizeElement` strips `class` from `<strong>` and `<em>` (`:143-147`).
- `buildConfig(allowedElements = null)` (`:153-194`):
  - Base: `ADD_URI_SAFE_ATTR: ["caption","filename","url"]`, `SAFE_FOR_XML: false` (so serialized HTML in `content` survives), `FORBID_ATTR: ["data-controller","data-action"]`.
  - With an allowlist: `ALLOWED_TAGS` = declared tags (lowercased), `ALLOWED_ATTR` = the base list, `ADD_ATTR` = a function `(attr, tag) => tagAttributes[tag]?.includes(attr)` (per-tag attributes), and optional `ALLOWED_URI_REGEXP` widened with declared `uriSafeSchemes` (for example `gid`). Executable schemes (`*script`, `data`) are refused (`sanitization_helper.js:429-457`).
  - With no allowlist (`null`), DOMPurify's own defaults apply.
- `helpers/sanitization_helper.js`: `url` is URI-safe, so the hook decides. The value is allowed if it matches DOMPurify's IS_ALLOWED_URI. A `data:` URI is allowed only on the **attachment tag** (`Lexxy.global.attachmentTagName`) (`:480-492`). There is a GHSA and HackerOne history note in the file.

### `src/editor/sanitizer.js` (`EditorSanitizer`)
- Per-editor, stored in a `WeakMap<LexicalEditor, EditorSanitizer>`.
- `register(editor, allowedElements)` is called from `$initialEditorState`, via `#configureSanitizer` (`editor.js:848-850`). The allowlist is the importable tags (`editor._htmlConversions.keys()` without `#text`-style keys, which covers every tag any registered node can import) plus the extensions' `allowedElements`:
  - Attachments: `{tag: attachmentTagName, attributes: [alt, caption, content, content-type, data-direct-upload-id, data-sgid, filename, filesize, height, presentation, previewable, sgid, url, width]}` (`attachments_extension.js:15-29`).
  - Tables: `figure`, `tbody`.
  - FormatEscape: `ol[start]`, `li[value]`.
- `for(editor)` returns the registered sanitizer or a lazily built fallback with **no allowlist** (DOMPurify defaults). This covers consumers who register the nodes in a non-Lexxy editor.
- `sanitize(html, {safeForXml})`: `safeForXml` turns on `SAFE_FOR_XML` for re-inflating stored custom attachment HTML (`custom_action_text_attachment_node.js:93`). The value hop is lax so the `content` attribute (full of HTML and comments) survives.
- Where sanitization runs:
  1. `editor.value` (every read of the exported HTML).
  2. `CustomActionTextAttachmentNode.createDOM` (strict).
  3. Server side (Loofah) and in the rendered view, which are outside the JS (see AGENTS.md).
- Clipboard and initial HTML are **not** sanitized before import. The Lexical importer only creates known nodes, and the output is sanitized.

---

## 4. Controllers

### Contents (`src/editor/contents.js`)
The document-mutation API. It holds `editorElement` and `editor`; `dispose()` nulls them.
- `insertHtml(html, {tag})` → `insertDOM(parseHtml(html), {tag})`.
- `insertDOM(doc, {tag})` (`:40-50`) runs in `editor.update(..., {tag})`:
  - if `PASTE_TAG`, `PastedContentFormatter(doc).format()`;
  - `nodes = editorElement.$generateNodesFromDOM(doc)`;
  - if pasting, dispatch `SELECTION_INSERT_CLIPBOARD_NODES_COMMAND` (the Clipboard handles the single-link case). Otherwise, or if not handled, `#insertUploadNodes(nodes)` (when every node is an ActionTextAttachmentNode, the Uploader inserts them, gallery-aware) `|| insertAtCursor(...nodes)`.
  - This mirrors Lexical's `$insertGeneratedNodes` (`lexical/lexical-clipboard/src/clipboard.ts:469-481`).
- `insertText(text, {tag})` splits on newlines into one paragraph containing LineBreakNodes.
- `insertAtCursor(...nodes)` uses `NodeInserter.for(#insertableSelection())`, where the insertable selection is the current selection, or `root.selectEnd()` when it is null or an empty NodeSelection.
- **NodeInserter strategies** (`contents/node_inserter.js`). The first match of these wins; otherwise the raw selection's `insertNodes` is used:
  - `CodeNodeInserter`: inside a code block, text and line breaks become code children; nodes that already exist are converted to text; non-joinable nodes such as attachments are inserted after the block. Uses a NodeCaret.
  - `ShadowRootNodeInserter`: anchor on a table cell or other shadow root; appends a paragraph and inserts there.
  - `NodeSelectionNodeInserter`: overrides Lexical's `NodeSelection.insertNodes`, which **removes the selected nodes** (`lexical/lexical/src/LexicalSelection.ts:400-417`). Lexxy inserts after the selection instead, wrapping inline nodes with `$makeSafeForRoot` when inserting at root level (error #99).
  - `ListItemNodeInserter`: block decorators (attachments) split the outermost list with `$splitNode` and land between the halves.
  - `BlockContainerNodeInserter`: an element point on a container of blocks (for example a quote). Runs `$normalizeSelection__EXPERIMENTAL` first to avoid invariants #211 and #212.
- Block formatting: `applyParagraphFormat`, `applyHeadingFormat(tag)`, `applyUnorderedListFormat`, `applyOrderedListFormat`, `clearFormatting`, `toggleCodeBlock`, `toggleBlockquote`.
  - `applyParagraphFormat` and `applyHeadingFormat` use `$expandSelectionToLineBreaksAndSplitAtEdges` + `$setBlocksType`, so only the lines between `<br>`s in a paragraph convert.
  - List formats inside a quote wrap the quoted blocks in lists manually (`#insertListInsideQuote`). Otherwise they split paragraphs at inner line breaks and dispatch `INSERT_UNORDERED_LIST_COMMAND` / `INSERT_ORDERED_LIST_COMMAND`.
  - `clearFormatting`: format 0 and empty style on every selected text node, `$toggleLink(null)`, unwrap quotes, then `$setBlocksType` paragraph.
  - `toggleCodeBlock`: unwraps if everything is already code, otherwise creates a `CodeNode("plain")` after the outermost elements and moves them in via `insertAtCursor` (CodeNodeInserter).
  - `toggleBlockquote`: unwrap or wrap the top-level elements.
- Links: `hasSelectedText()`, `createLink(url)` (inserts a LinkNode with the URL as its text and returns its key), `createLinkWithSelectedText(url)`.
- Prompt support:
  - `textBackUntil(string)` returns the query text from the trigger to the next boundary. The query can extend past the cursor. Boundaries: whitespace, or punctuation that is not between word characters (`:196-248`).
  - `containsTextBackUntil(string)`.
  - `replaceTextBackUntil(stringToReplace, nodes)` splits the anchor text node, inserts the replacement nodes, adds a trailing text node (a space if there was nothing after), may append a LineBreak, and places the cursor.
- Uploads:
  - `uploadFiles(files, {selectLast, altText})` filters with `editorElement.acceptsFile(file)` (the cancelable `lexxy:file-accept` event), then runs `Uploader.for(...).$uploadFiles()` in an update. It sets `altText` on a single node, and with `selectLast` selects the end of the last node and normalizes a shadow-root selection.
  - `$createUploadNode(file)` builds an `ActionTextAttachmentUploadNode` with `uploadUrl = directUploadUrl` and `blobUrlTemplate`.
  - `$createPendingUploadNode(file)` sets `uploadUrl: null`, meaning the upload is managed externally (for example by a native bridge).
  - `insertPendingAttachment(file)` and `insertPendingAttachments(files)` return handle(s) with `setAttributes(blob)` (runs `$showUploadedAttachment` under HISTORY_MERGE), `setUploadProgress(n)`, and `remove()`. This is the host or native-bridge upload API.
- HTML replacement: `replaceNodeWithHTML(nodeKey, html, {attachment})` and `insertHTMLBelowNode(nodeKey, html, {attachment})`, used by `lexxy:insert-link`. They create a `CustomActionTextAttachmentNode({sgid, contentType (default text/html), innerHtml})` if that content type is permitted, and plain imported HTML otherwise.

### `contents/uploader.js`
`Uploader.for(editorElement, files, {pending})` returns a `GalleryUploader` when more than one previewable image is uploaded, when the selection is on a previewable image, or when the cursor is right after a gallery edge.
- `$uploadFiles` = `$createUploadNodes` + `$insertUploadNodes`.
- `GalleryUploader` finds or creates an `ImageGalleryNode`, splices images in at the computed position, and inserts non-images after the gallery.

### Selection (`src/editor/selection.js`)
Wraps selection queries and decorator navigation.
- Public getters:
  - `hasNodeSelection`, `cursorPosition` (`{x, y, fontSize}` relative to the root; uses a zero-width marker span when the rect is unreliable; used by prompt popovers);
  - `placeCursorAtTheEnd()`, `selectedNodeWithOffset()`;
  - `getFormat()`, which returns `{isBold, isItalic, isStrikethrough, isUnderline, isHighlight, isInLink, isInQuote, isInHeading, isInCode, headingTag, isInList, listType, isInTable}`;
  - `nearestNodeOfType(Klass)`, `hasSelectedWordsInSingleLine`, `isInsideList`, `isInsideBlockQuote`, `isIndentedList`, `isInsideCodeBlock`, `isTableCellSelected`, `isOnPreviewableImage`, `previewableImageNode`, `isAtNodeStart`;
  - `nodeAfterCursor`, `nodeBeforeCursor`, `topLevelNodeAfterCursor`, `topLevelNodeBeforeCursor` (these use visual first and last line detection via `getBoundingClientRect`).
- Most of these must run inside a read or update, because they call `$getSelection` directly.
- Registered behaviours:
  - `CLICK_COMMAND` (LOW): clicking a decorator node creates a NodeSelection (`#listenForNodeSelections` `:373-388`). A root listener handles `lexxy:internal:move-to-next-line` (select the next block or append a paragraph).
  - Arrow keys (LOW, through `handlingDefault`): move from text into an adjacent decorator as a NodeSelection, or step off a selected decorator. Shift+arrow on a selected decorator converts it to a range and extends it.
  - `DELETE_CHARACTER_COMMAND` (LOW): `#selectDecoratorNodeBeforeDeletion`. The first Backspace next to an attachment selects it rather than deleting it. It also has special handling for empty list items (`#removeEmptyListItem`) and for collapsing a list item into a paragraph.
  - `SELECTION_CHANGE_COMMAND`: at LOW it syncs the `node--selected` class on NodeSelection DOM; at CRITICAL it adds `SKIP_DOM_SELECTION_TAG` when focus is in another element, so a stale selection doesn't pull focus back.
  - A capture keydown handler on the root implements a Chrome workaround: ArrowUp/Down past a `[data-lexical-cursor]` block cursor.
  - `#clearStaleInlineCodeFormat`: an update listener removes the `code` format from a collapsed selection when no code-formatted content backs it, via `setTimeout` plus an update.

### Clipboard (`src/editor/clipboard.js`)
Registers `PASTE_COMMAND` (NORMAL, which beats rich text's EDITOR-priority handler at `lexical/lexical-rich-text/src/index.ts:1086`) and `SELECTION_INSERT_CLIPBOARD_NODES_COMMAND` (NORMAL).

`paste(event)` decision tree:
1. No `clipboardData` → return false (Lexical default).
2. Cursor inside a CodeNode → `selection.insertRawText(text/plain)` under `PASTE_TAG`.
3. Only `text/plain`, or "only a URL" (`#isOnlyURLPasted`: uri-list shapes; or plain text that is an autolinkable URL with no HTML, or HTML that is just that bare link; never when the data is Lexical clipboard data `application/x-lexical-editor`) → `#pastePlainTextOrURL`, which reads the item asynchronously with `getAsString`:
   - If `isAutolinkableURL(text)` (`/^(?:[a-z0-9]+:\/\/|www\.)\S+$/i`), `#pasteURL`. With selected text it becomes `createLinkWithSelectedText`. Otherwise `createLink(url)` inserts a LinkNode and dispatches `lexxy:insert-link` with `replaceLinkWith` and `insertBelowLink` callbacks (for embeds and unfurls).
   - Else, if markdown is supported, `#pasteMarkdown(text)`.
   - Else `$insertDataTransferForRichText(clipboardData, selection, editor)` under PASTE_TAG.
4. Otherwise, only when attachments are supported (`#handlePastedFiles`):
   - HTML that is a single `<img>` plus files: upload the files with that `alt`.
   - HTML that is not Lexical clipboard data: `contents.insertHtml(html, {tag: PASTE_TAG})`, which goes through the PastedContentFormatter, Lexxy's `$generateNodesFromDOM` (data-URI image → upload node, disallowed attachments filtered out), and NodeInserter.
   - Files only: `uploadFiles`, preserving the scroll position (a Safari fix).
   - Anything else returns false, which leaves Lexical rich text's default paste. That also covers Lexical-to-Lexical copies with the same namespace `"Lexxy"`, which go through `$insertDataTransferForRichText` and JSON nodes.
   - When attachments are **disabled**, everything except cases 2 and 3 falls through to Lexical's default paste. Lexical's default path uses `@lexical/html`'s `$generateNodesFromDOM`, not Lexxy's wrapper.

`SELECTION_INSERT_CLIPBOARD_NODES_COMMAND` handler (`:64-70`): if the parsed nodes are exactly one link, or a paragraph containing only one link, whose text equals its URL, it inserts a LinkNode (or toggles a link on the selected text) and fires `lexxy:insert-link` via `$onUpdate`. This covers Chromium's `text/html` for copied URLs and Lexical's own rich-text path.

Markdown paste (`#pasteMarkdown` `:197-213`):
- `html = parsePastedMarkdown(text)`, then `doc = parseHtml(html)`.
- If the result is a single `<p>` containing only text and `<br>`, the text had no markdown structure, so it is inserted verbatim with `contents.insertText(text, PASTE_TAG)`. This preserves backslashes and runs of spaces, such as Windows paths.
- Otherwise it dispatches `lexxy:insert-markdown` (listeners may mutate `document`, and `addBlockSpacing()` inserts `<p><br></p>` spacer paragraphs between blocks, `html_helper.js:47-54`), then `contents.insertDOM(doc, PASTE_TAG)`.

### `helpers/markdown_helper.js`
A private `new Marked({breaks: true, renderer: {html: renderPastedHtmlToken}}).use({tokenizer: {code: () => undefined}})`:
- An isolated instance, so a host's `marked.use` can't leak in.
- GFM is on (tables parse), and `breaks` turns single newlines into `<br>`.
- The **indented code block tokenizer is disabled** (only fenced code creates code blocks).
- The raw-HTML renderer escapes unknown or custom tags (`HTMLUnknownElement` or names containing a hyphen) to literal text. For example, WEBVTT `<v Name>` stays as text, and a pasted `<action-text-attachment>` can never materialize an attachment from plain text. Known tags pass through.

### PastedContentFormatter (`contents/pasted_content_formatter.js`)
Runs only for PASTE_TAG `insertDOM`. `format()` order:
1. `#inlinePreservableStyles`: Office stylesheet `p { margin-top/bottom }` values are inlined when all matching rules agree. It builds a constructable `CSSStyleSheet`, because a DOMParser document has no `styleSheets` in WebKit.
2. `#stripStyleElements`: remove `<style>` so Excel cascade colours don't leak.
3. `#unwrapPlaceholderAnchors`: unwrap `<a href="">` and `<a href="#">`.
4. `#stripTableCellColorStyles`: remove color and background on `td` and `th`.
5. `OfficeFormatter.format()` (`pasted_content_formatter/office_formatter.js`): rebuilds real `<ul>`/`<ol>` from Word's `mso-list:lN levelN` paragraphs. It chooses ol or ul from the `mso-list:Ignore` marker text and normalizes to the shallowest level.
6. `#unwrapWrappedListChildren`, `#nestStrayListChildren` (Gmail-style sublists as direct children of the list), `#stripStrayListChildren`.
7. `#replaceGmailEmojiImgTags`: `img[data-emoji]` becomes the emoji text.

### Style canonicalization (in `extensions/highlight_extension.js` + `helpers/format_helper.js`)
- On import, `<mark>`, and styled `<span>`/`<em>`/`<strong>`/`<del>` (from TrixContentExtension), go through `$applyHighlightStyle` (`highlight_extension.js:65-76`). It appends `color` and `background-color` to the TextNode style and, under PASTE_TAG, marks the node with NodeState `hasPastedStyles`.
- A TextNode transform, `$canonicalizePastedStyles` (`:454-468`), runs `StyleCanonicalizer`s for color and background-color. Each canonicalizer is built from the configured `highlight.buttons` values plus `highlight.permit` values. A pasted value maps to the matching allowed value by **computed-style equality**; values are resolved through the strictly contained `styleResolverRoot()` (`helpers/style_resolver_root.js`) in batch (`format_helper.js:95-112`). A value with no match is removed. The selection style and format are then synced.
- Other transforms keep the `highlight` format bit in sync with the presence of the style (`$syncHighlightWithStyle`), including for CodeHighlightNodes through a direct `__format` bit (`IS_HIGHLIGHT = 1<<7`) because `CodeHighlightNode.setFormat` is a no-op.
- `TOGGLE_HIGHLIGHT_COMMAND` / `REMOVE_HIGHLIGHT_COMMAND` → `$toggleSelectionStyles`, which uses `$patchStyleText` or, inside code blocks, a nested discrete update with `skipTransforms`.
- `$registerPreConversion` pushes a `pre` converter directly into `editor._htmlConversions`. This works around the builder's `Object.assign` merge of `html.import` per tag (`LexicalBuilder.ts:459-461`), where TrixContent's `pre` would otherwise overwrite it. It extracts `<mark>` ranges into `pendingCodeHighlights`, and CodeHighlightingExtension's tokenizer re-applies them after Prism retokenizes the block.

### CommandDispatcher (`src/editor/command_dispatcher.js`)
- `COMMANDS` (`:30-58`) is a list of string names. For each `cmd`, `registerCommand(cmd, this["dispatch"+Capitalized], 0)` (priority 0 = EDITOR). **Lexical commands are keyed by identity in `editor._commands`, so plain strings work as command types** (`lexical/lexical/src/LexicalUpdates.ts:790-830`, where `commandListeners.get(type)` is called and handlers run inside `updateEditorSync`, so `$getSelection` is available).
- The toolbar calls `editor.update(() => editor.dispatchCommand(button.dataset.command, button.dataset.payload))` (`elements/toolbar.js:137-146`), adding `SKIP_DOM_SELECTION_TAG` for keyboard activation outside dropdowns so focus stays on the toolbar. Dropdowns dispatch `"link"`, `"unlink"`, `"toggleHighlight"`, and heading commands. Table tools dispatch `insertTableRowAfter` and similar string commands registered in `TablesExtension`.
- Mapping from string command to Lexical:
  - `bold`/`italic`/`strikethrough`/`underline` → `FORMAT_TEXT_COMMAND`.
  - `toggleHighlight(styles)` / `removeHighlight` → the Highlight extension commands.
  - `link(url)`: a collapsed selection not in a link inserts an `AutoLinkNode(url)` with the URL as text; otherwise `$toggleLink(url)`.
  - `unlink`: `adapter.unlinkFrozenNode?.()` for NativeAdapter, or `$toggleLink(null)`.
  - `setFormatHeadingLarge`/`Medium`/`Small` → `config.headings[0..2]` → `contents.applyHeadingFormat`.
  - `setFormatParagraph`, `applyHeadingFormat(tag)`, `clearFormatting`.
  - `insertUnorderedList`/`insertOrderedList` toggle: if already in a list of that type, convert to paragraph.
  - `insertQuoteBlock` → `toggleBlockquote`.
  - `insertCodeBlock`: if `hasSelectedWordsInSingleLine`, toggle inline `code` (first stripping other inline formats so one `<code>` results); otherwise `toggleCodeBlock`.
  - `setCodeLanguage(lang)`.
  - `insertHorizontalDivider` → `$insertNodeToNearestRoot(new HorizontalDividerNode)`.
  - `uploadImage` / `uploadFile`: a hidden `<input type=file multiple accept="image/*,video/*"?>` is clicked, then `uploadFiles`.
  - `insertTable` → `INSERT_TABLE_COMMAND {rows:3, columns:3, includeHeaders:true}`.
  - `undo`/`redo` → `UNDO_COMMAND`/`REDO_COMMAND`.
- Keyboard:
  - ArrowRight at the end of an inline-code run (the last text node) drops the code format (NORMAL).
  - Tab in a list → `INDENT_CONTENT_COMMAND`, Shift+Tab → `OUTDENT_CONTENT_COMMAND` (only if the list is indented). Tab in a code block with a collapsed selection returns true (lets rich text insert a tab).
  - `INSERT_LINE_BREAK_COMMAND` and `INSERT_PARAGRAPH_COMMAND` at HIGH run `$normalizeBlockContainerSelection()` and return false.
- External file drag and drop (attachments only): a root listener adds dragenter, dragleave, dragover, and drop. It keeps a drag counter, the `lexxy-editor--drag-over` class, saves and restores the selection from before the drag, and calls `uploadFiles(files, {selectLast: true})`. It ignores internal drags whose types start with `application/x-lexxy-`.

### Adapters (`src/editor/adapters/*`)
They abstract "who receives editor state notifications" and "how to freeze editing", mainly for Hotwire Native / iOS / Android bridges.
- `BrowserAdapter` (the default): no-op `dispatchAttributesChange`, `dispatchEditorInitialized`, `freeze`, `thaw`, and `unlinkFrozenNode() → false`.
- `NativeAdapter(editorElement)`:
  - emits `lexxy:attributes-change` and `lexxy:editor-initialized` (see the events table);
  - `freeze()` remembers the LinkNode key at the anchor (`frozenLinkKey`) and sets `contentEditable="false"`, so a native sheet can take focus without losing the selection;
  - `thaw()` sets `contentEditable="true"`;
  - `unlinkFrozenNode()` unwraps the frozen link and selects its text, which the `unlink` command uses.
- Install one with `editorElement.registerAdapter(new NativeAdapter(el))`.

---

## 5. Prompt subsystem (sources in `src/editor/prompt/*`; element in `src/elements/prompt.js`)

- `<lexxy-prompt trigger="@" name="mention" src? remote-filtering? supports-space-in-searches? only-at? insert-editable-text? empty-results? vertical-direction?>` is a child of the editor. Its `<lexxy-prompt-item search="…" sgid="…">` children contain `<template type="menu">` (the list item) and `<template type="editor" content-type? sgid?>` (what gets inserted).
- Source selection (`prompt.js:85-96`):
  - with `src` and `remote-filtering` → `RemoteFilterSource`;
  - with `src` only → `DeferredPromptSource`;
  - otherwise → `InlinePromptSource(child items)`.
- `BaseSource`: `buildListItems(filter)` and `promptItemFor(li)` are template methods. `buildListItemElementFor(item)` clones `template[type=menu]` into `li[role=option].lexxy-prompt-menu__item`. `loadPromptItemsFromUrl(url)` fetches HTML and collects `lexxy-prompt-item` elements.
- `LocalFilterSource`: filters by `filterMatchPosition(item.search, filter)`, a diacritic-insensitive match at the start of a word (`string_helper.js`). It sorts by match position, caps results at 100, and maps each `li` back to its prompt item with a `WeakMap`.
- `InlinePromptSource` and `DeferredPromptSource` both extend it; Deferred fetches once and caches.
- `RemoteFilterSource`: a `debounceAsync` of 200 ms fetches `src?filter=<q>` on each query and caps results at 100.
- Trigger detection: an editor update listener checks whether the text just before the cursor equals `trigger`, and whether the text before the trigger matches `only-at` (default pattern). It is skipped inside code blocks. The popover then refilters on `lexxy:change` (debounced) and on keydown. Popovers are positioned with `selection.cursorPosition`.
- Insertion (`prompt.js:484-531`): `stringToReplace = trigger + contents.textBackUntil(trigger)`.
  - With `insert-editable-text`: templates are imported with `$generateNodesFromDOM` and inserted as normal nodes.
  - Otherwise each `template[type=editor]` becomes a `CustomActionTextAttachmentNode({sgid (template sgid or item sgid), contentType (template content-type or `application/vnd.<ns>.<name>`), innerHtml})`, with space text nodes between them, and is passed to `contents.replaceTextBackUntil`.
  - Templates with unpermitted content types are filtered out, and the prompt doesn't activate at all when no content type is permitted or attachments are off (unless `insert-editable-text`).

---

## 6. Attachments subsystem

### Nodes (brief)
- `ActionTextAttachmentNode` (DecoratorNode, `nodes/action_text_attachment_node.js`):
  - `importDOM` handles `<attachmentTagName>` (sgid, url, previewable, alt, caption, content-type, filename, filesize, width, height), plus `<img>` and `<video>`.
  - `isInline()` is true only when it is not a direct child of a root or shadow root (for example inside a gallery).
  - `getTextContent` returns `[caption|filename]\n\n`.
  - `this.editor = $getEditor()` is captured at construction.
  - `patchAndRewriteHistory(patch)` and `replaceAndRewriteHistory(node)` dispatch `REWRITE_HISTORY_COMMAND`.
  - `focusCaption()` → `captionEditor.open(key)`.
  - It polls preview status for non-image previewables (`pendingPreview`).
- `ActionTextAttachmentUploadNode` (transient; `importDOM` returns null and `exportDOM` returns `{element: null}`):
  - `createDOM` starts the upload once, guarded by `progress !== null`. A local preview uses `FileReader` (`helpers/upload_helper.js` `loadFileIntoImage`) and records dimensions through a history rewrite. It shows a `<progress>`.
  - `#startUploadIfNeeded` (`:149-176`) skips when `uploadUrl` is null (a bridge-managed upload) or there is no File. Otherwise it dynamically imports **`@rails/activestorage` DirectUpload** with `new DirectUpload(file, uploadUrl, this)`. The delegate sets `withCredentials` when `authenticatedUploads` is on and tracks the XHR in `editorElement.uploadRequests` (keyed by node key) so the upload can be **aborted when the node is destroyed** (`AttachmentsExtension#handleUploadMutations`).
  - Progress is written with `patchAndRewriteHistory({progress})`. On error the node gets `uploadError: true` and the error DOM.
  - On success `$showUploadedAttachment(blob)` replaces the node via `replaceAndRewriteHistory` with an `ActionTextAttachmentNode` built from the blob: `attachable_sgid`, `content_type`, `filename`, `byte_size`, `previewable`, `preview_status_url`. `src` is `blob.url` if previewable, else `blobUrlTemplate` with `:signed_id` and `:filename` substituted. For images, `previewSrc` is an object URL.
- `CustomActionTextAttachmentNode`: an inline DecoratorNode for mentions and embeds.
  - `importDOM` requires a `content` attribute and preserves spaces next to the node. The `content` value is parsed as JSON for legacy data and falls back to raw HTML.
  - `createDOM` sanitizes `innerHtml` strictly.
  - Exports `sgid`, `content`, and `content-type`.
  - `getReadableTextContent()` returns `plainText`.
- `ImageGalleryNode` groups previewable images.

### `RewritableHistoryExtension` (`extensions/rewritable_history_extension.js`)
- `REWRITE_HISTORY_COMMAND` payload: `{[nodeKey]: {patch?, replace?}}`.
- It applies the change to the current state immediately (a discrete update tagged `HISTORY_MERGE` + `SKIP_SCROLL_INTO_VIEW`, and `SKIP_DOM_SELECTION` when not focused).
- It also rewrites **every history entry** (undo stack, current, redo stack) by cloning the EditorState with a fresh `_nodeMap`, so undo/redo never resurrects an in-flight upload node or a stale progress value. It relies on internals: `historyState.undoStack/redoStack/current`, `editorState._nodeMap`, and `$cloneWithProperties`.
- The history state comes from `state.getDependency(HistoryExtension).output.historyState.value`.

### `AttachmentsExtension` (`extensions/attachments_extension.js`)
Enabled when `supportsAttachments`.
- Registers the nodes and the sanitizer allowlist.
- `ActionTextAttachmentNode` transform `$extractAttachmentFromParagraph`: lifts block attachments out of paragraphs, which Lexical creates when importing attachments nested in `<div>`.
- `DELETE_CHARACTER_COMMAND` → `$collapseIntoGallery`: merges galleries around a deleted empty paragraph, joins at gallery edges, and moves the selection before a gallery.
- `KEY_TAB_COMMAND` (HIGH) → focuses the caption of the selected attachment.
- A mutation listener on upload nodes counts in-flight uploads (validity: customError "Please wait for all files to upload") and aborts XHRs on destroy.
- Instantiates:
  - **AttachmentDragAndDrop** (`editor/attachments/drag_and_drop.js`): internal drag of `figure.attachment` with MIME `application/x-lexxy-node-key`. `DRAGSTART_COMMAND` and `DROP_COMMAND` at HIGH beat rich text's handlers (`lexical/lexical-rich-text/src/index.ts:972,1008`). `dragover` is rAF-throttled and resolves the drop target: gallery merge onto an image, reorder within a gallery, split a list at an `li`, or between top-level blocks (normalized to "after the previous sibling"). It shows `lexxy-drop-target--*` classes. On drop it moves the node and sets the selection to null to avoid a second history entry.
  - **AttachmentKeyboardMove** (`keyboard_move.js`): `KEY_DOWN_COMMAND` HIGH; **Alt+Shift+Arrow** on a selected attachment. Up/Down move it among blocks (join, form, or leave a gallery; swap with the neighbour; skip provisional paragraphs). Left/Right reorder within a gallery. It uses NodeCaret (`$getSiblingCaret(...).insert`), keeps the NodeSelection, announces the result through the live region ("Attachment moved up", "Gallery created", …), and scrolls into view in an rAF.
  - **AttachmentFakeSelection** (`fake_selection.js`): Lexical clears the DOM range on a NodeSelection, so this appends a `span.lexxy-fake-selection` with the attachment label (caption, alt, or filename) to the selected figure and parks a DOM range on it for screen readers. This happens only while the root itself is focused.
  - **CustomAttachmentLabels** (`custom_attachment_labels.js`): exposes a mention's label (`exposeLabel` / `restoreLabel`) when it is node-selected or when the caret is within one character of it.

### `CustomAttachmentDragAndDropExtension` → `editor/attachments/custom/drag_and_drop.js`
Enabled with rich text. Drags inline custom attachments (MIME `application/x-lexxy-custom-attachment-key`) and drops them at a text caret (`caretFromPoint` → `$createRangeSelectionFromDom`) with a drop indicator.

### CaptionEditor (`editor/attachments/caption_editor.js`)
- Created only with rich text and attachments.
- A single `<textarea.lexxy-caption-editor>` is overlaid on `figcaption.attachment__caption--editable` of the node being edited. The overlay is positioned by rects, a ResizeObserver, and scroll.
- `open(key)` starts editing. Blur saves (`node.getWritable().caption = value`, tagged SKIP_DOM_SELECTION, discrete).
- Enter or Escape blurs and refocuses the root. Enter moves the selection after the node (or after the gallery if it was the last image); Escape re-selects the node.
- An update listener closes the overlay if the figure is re-rendered.

### AlternativeTextDialog (`editor/attachments/alternative_text_dialog.js`)
- Created by `<lexxy-attachment-toolbar>` (`elements/attachment_toolbar.js:62`), and shown only if `data-action-text-supports-alt !== "false"` (`:196`).
- A non-modal `<dialog>` anchored below the figure. Save writes `altText`, tagged HISTORY_PUSH + SKIP_DOM_SELECTION. Escape or Cancel closes it and restores focus. A click outside closes it without refocusing. Tab is trapped (`trapFocusAtTabBoundary`).

### UploadRequests (`editor/attachments/upload_requests.js`)
A Map from node key to XHR, with `track`, `forget`, `abort`, and `clear`. It is cleared on reset.

### Data-URI images (`helpers/inline_image_uri_helper.js`)
During a paste import, an `ActionTextAttachmentNode` whose `src` is `data:image/...;base64` becomes a File (`pasted-image-<ts>.<ext>`). If `acceptsFile` allows it, the node becomes an upload node that goes through DirectUpload; otherwise it is dropped. This keeps base64 out of stored HTML.

---

## 7. Helpers (important ones)

- `html_helper.js`:
  - `createElement(name, props, content)` assigns known properties directly, sets other keys as attributes, and writes `content` via innerHTML.
  - `parseHtml` uses DOMParser `text/html`.
  - `createAttachmentFigure`, `isPreviewableImage` (image/* but not svg), `dispatch`, `dispatchCustomEvent`, `addBlockSpacing`, `generateDomId`, `extractPlainTextFromHtml`, `isActiveAndVisible` (with a `checkVisibility` fallback).
- `listener_helper.js`:
  - `registerEventListener(el, type, fn, opts)` returns a deregister function that holds WeakRefs to the element and the listener.
  - `ListenerBin` has `track(...teardowns)` and `dispose()` (LIFO).
  - `handlingDefault(handler)` calls preventDefault when the handler returns truthy.
- `upload_helper.js`: `loadFileIntoImage(file, img)`, a FileReader data URL that resolves on the image's load.
- `storage_helper.js`: `bytesToHumanSize`, `extractFileName`, `parseAttachmentContent` (JSON first, for legacy), `mimeTypeToExtension`.
- `style_resolver_root.js`: a single `div[data-lexxy-style-resolver]` with `contain: strict; position: fixed; visibility: hidden` attached to the body. Children are added and removed inside it so computing styles doesn't invalidate styles across the whole page (a Basecamp performance fix).
- `sanitization_helper.js`: see §3.
- `format_helper.js`: highlight detection, `getHighlightStyles`, `StyleCanonicalizer`, `computeStyleValues`.
- `lexical_helper.js`:
  - `$createNodeSelectionWith`, `$singleSelectedNode`, `registerLabelledDecoratorSelection`, `$isShadowRoot`, `$makeSafeForRoot`, `getListType`, `announceFromEditor`, `isEditorFocused` (root contains activeElement), `$isAtNodeEdge`;
  - `extendTextNodeConversion` / `extendConversion`, which wrap another node's `importDOM` converter;
  - `$isBlankNode`, `$isListItemStructurallyEmpty`, `$textBeforeOffset`, `isAttachmentSpacerTextNode`;
  - `$expandSelectionToLineBreaksAndSplitAtEdges` and `$splitSelectedParagraphsAtInnerLineBreaks` (NodeCaret based);
  - `$isPointOnBlockContainer`, `$hasPointOnBlockContainer`, `$normalizeBlockContainerSelection` (#211/#212 workaround), `$consecutiveSiblingGroups`.
- `text_node_export_helper.js`: see §1 value export.
- `timing_helper.js`: `debounce`, `debounceAsync`, `delay`, `nextFrame`.
- `string_helper.js`: `dasherize`, `isAutolinkableURL`, `filterMatchPosition`, `parseBoolean`, etc.
- `csp_helper.js`: `getNonce()` from `meta[name=csp-nonce]`.
- `code_highlighting_helper.js`: `highlightCode(root)` handles `pre[data-language]:not([data-highlighted])`. `highlightElement` extracts code plus `<mark>`/`<a>` ranges in a single walk, runs `Prism.highlight`, then re-wraps those ranges.

---

## 8. Other extensions touching core behaviour (brief)
- **ProvisionalParagraph:** RootNode transforms insert and remove `ProvisionalParagraphNode`s, which give the caret a landing place around leading and trailing decorators. They are marked dirty on SELECTION_CHANGE (HIGH).
- **TrixContent:** `html.import` for Trix-style styled `em`/`span`/`strong`/`del` and `pre[language]`.
- **FormatEscape:** replaces CodeNode and ListItemNode with "early escape" versions; Enter on an empty quote line escapes the quote; ArrowDown at the end of a code block escapes it; quotes always keep a paragraph child. Allows `ol[start]` and `li[value]`.
- **LinkOpener:** Cmd+click (Mac) or Ctrl+click, and middle click, open links with `window.open(..., "noopener,noreferrer")` after `sanitizeUrl`. Toggles `data-links-openable` on the host while the modifier is held.
- **PreventLexicalTripleClick:** stops a capture-phase click with `detail === 3` so Lexical's triple-click handler (facebook/lexical#4512) doesn't run.
- **LineSeparators:** a TextNode transform converts `\n`, `\r`, U+2028, and U+2029 inside text into LineBreakNodes.
- **Tables:** `registerTablePlugin`, scrollable tables, WrappedTableNode (`<figure>` wrapper), and header-cell transforms. String commands `insertTableRowAfter/Before`, `insertTableColumnAfter/Before`, `deleteTableRow`, `deleteTableColumn`, `deleteTable`, and more.
- **Markdown leading-tag handler** (`editor/markdown/leading_tag_handler.js`): an update listener. When the user types an **opening** tag in front of text that already ends with the closing tag (for example typing `` ` `` before ``hello` ``, or `**` before `hello**`), it applies the text format. Lexical's shortcuts only fire when the closing tag is typed. It honours `intraword`, picks the longest tags first, skips history and collaboration updates, IME composition, and code blocks.
- `HORIZONTAL_DIVIDER` (`editor/markdown/horizontal_divider_transformer.js`): a multiline-element transformer. `---` becomes a HorizontalDividerNode followed by a new paragraph.
