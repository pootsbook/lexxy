# Action Text internals and the Lexxy integration

Refs: Rails main (actiontext 8.2.0.alpha, `actiontext/lib/action_text/gem_version.rb`). Lexxy 1.0.0 (this repo).
Paths below: `AT/` = `rails/rails@main:actiontext/`, `AS/` = `rails/rails@main:activestorage/app/javascript/activestorage/`, `LX/` = this repo root.

---

## 1. Action Text architecture (Rails main)

### 1.1 Model layer
- **`has_rich_text`**, `AT/lib/action_text/attribute.rb:53-92`. Defines `#{name}` (it builds the record if missing), `#{name}?`, and `#{name}=(body)`, which sets `rich_text_#{name}.body = body`. `store_if_blank: false` marks the record for destruction when the body is blank. Also defines `has_one :rich_text_#{name}` (polymorphic `record`, autosave, dependent destroy; the class is `EncryptedRichText` when `encrypted: true`) and the scopes `with_rich_text_x` and `with_rich_text_x_and_embeds`.
- **`ActionText::RichText`**, `AT/app/models/action_text/rich_text.rb`:
  - `cattr_accessor :editors` and `:editor` (lines 39-40) are the editor registry hook, set in the engine.
  - `serialize :body, coder: ActionText::Content` (line 42). The DB column is plain HTML. Loading wraps it in `Content`, and dumping calls `Content#to_html`.
  - `has_many_attached :embeds` plus `before_validation { self.embeds = body.attachables.grep(ActiveStorage::Blob).uniq }` (lines 58-62). This is how uploaded blobs become owned by the record, so unattached blobs aren't purged.
  - `to_plain_text`, `to_markdown`, `to_editor_html` (line 126), and the deprecated alias `to_trix_html` (line 109).
  - `ActiveSupport.run_load_hooks :action_text_rich_text` (line 134). The editor registry is installed on this hook.
- **`ActionText::Content`**, `AT/lib/action_text/content.rb` (line numbers below count from `grep -v '^#'` output, so they're approximate). It includes `Rendering`, `Serialization` and `ContentHelper`.
  - `initialize(content, canonicalize: true)` calls `fragment_by_canonicalizing_content`, which runs three steps in order:
    1. `Attachment.fragment_by_canonicalizing_attachments`. This is `fragment_by_converting_editor_attachments`, which calls **`RichText.editor.as_canonical(fragment)`** (`attachments/conversion.rb:13-17`), followed by `fragment_by_minifying_attachments`, which empties the `inner_html` of every `<action-text-attachment>` (`attachments/minification.rb:11-15`).
    2. `AttachmentGallery.fragment_by_canonicalizing_attachment_galleries`. A gallery `<div>` gets reduced to a bare `<div>` holding the inner HTML.
    3. `MarkdownConversion.fragment_by_unwrapping_raw_markdown_tags`, which removes the reserved `<action-text-markdown>` element.
  - `attachables` → `Attachable.from_node` for each attachment node. `attachments` → `Attachment.from_node` with full attributes.
  - `render_attachments(&block)` replaces each attachment node. It **sanitizes any `content` attribute** with `sanitize_content_attachment` before yielding.
  - **`to_editor_html`** is `render_attachments(&:to_editor_attachment)`, then `RichText.editor.as_editable(fragment).to_html`.
  - `to_s` is `to_rendered_html_with_layout`, which renders partial `action_text/contents/_content` inside layout `layouts/action_text/contents/_content` (`<div class="trix-content">`). Rails still emits the `trix-content` class here even when a different editor is configured.
  - `run_load_hooks :action_text_content` at the end of the file. Lexxy installs its sanitizer allowlists on this hook.
- **`ActionText::Fragment`**, `AT/lib/action_text/fragment.rb`. Wraps a Nokogiri HTML5 fragment (HTML4 if Nokogiri has no HTML5). `replace(selector) { |node| new_node }` is non-destructive: it `dup`s the source. It also provides `find_all`, `to_plain_text`, `to_markdown` and `to_html`.
- **`Serialization`**, `AT/lib/action_text/serialization.rb`. `load(html)` returns `Content.new`. `dump` returns `content.to_html`, or `new(str).to_html` for a String, so **a raw String assigned to `body` is canonicalized on the way in**.
- **`Rendering`**, `AT/lib/action_text/rendering.rb`. A thread-local `renderer` (set per request by the engine's `around_action`, `engine.rb:106-114`), with a fallback to `ActionController::Base.renderer`. `Content.render` is what renders attachment partials outside a view.

### 1.2 Attachments and attachables
- **`ActionText::Attachment`**, `AT/lib/action_text/attachment.rb`:
  - `mattr_accessor :tag_name, default: "action-text-attachment"`. Configured through `config.action_text.attachment_tag_name` (`engine.rb:23,123-125`).
  - `ATTRIBUTES = %w(sgid content-type url href filename filesize width height previewable presentation caption alt content)` (line 25). **`alt` is new on main.** Lexxy feature-detects it: `LX/lib/lexxy.rb:5-7`.
  - `from_node`, `from_attachable(attachable, attrs)` (built from `to_rich_text_attributes`), and `from_attributes`.
  - `full_attributes` = node attributes, merged with attachable attributes, merged with the sgid. `with_full_attributes` builds a new node from those.
  - `to_plain_text` and `to_markdown` delegate to `attachable_plain_text_representation(caption)` and `attachable_markdown_representation`.
  - `delegate_missing_to :attachable`, so partials can call `blob.caption` or `blob.alt` through the Attachment wrapper (`remote_image.try(:alt)` and `blob.try(:alt)` work this way).
- **`ActionText::Attachable`** (concern), `AT/lib/action_text/attachable.rb`:
  - **`Attachable.from_node(node)`** (lines 31-41) resolves in this order:
    1. `GlobalID::Locator.locate_signed(sgid, for: "attachable")`
    2. `ContentAttachment.from_node` (`content-type` matches `/html/` and a `content` attribute is present)
    3. `RemoteImage.from_node` (an absolute URL and an `image/*` content type)
    4. `MissingAttachable.new(sgid)`

    **Lexxy prepends a step between 3 and 4.**
  - Instance methods: `attachable_sgid` (`to_sgid(expires_in: nil, for: "attachable")`), `attachable_content_type`/`filename`/`filesize`/`metadata`, `previewable_attachable?`, `to_rich_text_attributes`.
  - Three partial-path hooks:
    - **`to_attachable_partial_path`** is used for rendering the show page and defaults to `to_partial_path`.
    - **`to_editor_content_attachment_partial_path`** (lines 128-130) is used to render the `content` attribute sent to the editor, and also defaults to `to_partial_path`. `to_trix_content_attachment_partial_path` is its deprecated alias.
    - `to_missing_attachable_partial_path`.
  - `read_attribute_for_serialization`/`attribute_names_for_serialization` add **`attachable_sgid`** to `as_json`. This is why the DirectUpload JSON response contains `attachable_sgid`.
- **Blob as attachable** (`AT/lib/action_text/engine.rb:51-86`). `on_load(:active_storage_blob)` includes `Attachable`. It sets `previewable_attachable?` to `representable?` and defines the plain-text and markdown representations. **`to_editor_content_attachment_partial_path` returns nil** (line 82), so blobs never get a `content` attribute in editor HTML. Blobs render through `AT/app/views/active_storage/blobs/_blob.html.erb` (representation resized to 1024x768, or 800x600 in a gallery, with `alt: blob.try(:alt)`).
- **`Attachables::ContentAttachment`**, `AT/lib/action_text/attachables/content_attachment.rb`. For sgid-less HTML content attachments (such as a Trix horizontal rule). It renders `content` via a nested `Content`, using the partial `_content_attachment.html.erb`.
- **`Attachables::RemoteImage`**, `remote_image.rb:11-15`. Requires `AssetUrlHelper::URI_REGEXP`, i.e. an absolute URL (this changed recently per the CHANGELOG). Partial `_remote_image.html.erb`.
- **`Attachables::MissingAttachable`**. Renders "☒" in both the partial and plain text. `to_partial_path` uses `model.to_missing_attachable_partial_path` when the sgid's model constant exists.
- **`AttachmentGallery`**, `AT/lib/action_text/attachment_gallery.rb`. The selector is `div:has(action-text-attachment[presentation=gallery] + action-text-attachment[presentation=gallery])`, and every child must be a gallery attachment or whitespace. It renders `action_text/attachment_galleries/_attachment_gallery` (`<div class="attachment-gallery attachment-gallery--N">`) as a *layout* around the attachments.
- **`TrixAttachment`**, `AT/lib/action_text/trix_attachment.rb` (deprecated on main). Converts between `<figure data-trix-attachment='{json}' data-trix-attributes='{caption,presentation}'>` and a plain attributes hash (camelCase keys, typecast values). `Attachments::TrixConversion` is a deprecated shim.
- **`PlainTextConversion`**. A `BottomUpReducer` over the DOM with `plain_text_for_<tag>_node` methods (blocks, lists, br, text, etc.). `MarkdownConversion` (new on main) mirrors it.

### 1.3 Rendering and sanitization (`AT/app/helpers/action_text/content_helper.rb`)
- `mattr_accessor :sanitizer` (default `Rails::HTML4::Sanitizer.safe_list_sanitizer.new`, replaced by `config.action_text.sanitizer_vendor` in `engine.rb:127-133`), plus `:allowed_tags`, `:allowed_attributes` and `:scrubber`.
- **`render_action_text_content(content)`** (line 14) sets `prefix_partial_path_with_controller_namespace = false` and returns `sanitize_action_text_content(render_action_text_attachments(content))`.
- `render_action_text_attachments` (line 37) fills each non-gallery attachment node's `inner_html` with `render_action_text_attachment(attachment, locals: {in_gallery: false})`, then renders galleries with the gallery partial as a layout.
- `render_action_text_attachment` (line 54) renders `partial: attachment.to_attachable_partial_path` with `as: model_name.element`. For example, a `Person` is passed to `people/_person` as `person`.
- `sanitize_action_text_content` (line 28) runs Loofah/rails-html-sanitizer with `sanitizer_allowed_tags` and `sanitizer_allowed_attributes` on the fully rendered HTML, then marks it `html_safe`.
- Defaults (lines 68-74): the sanitizer's tags plus `action-text-attachment figure figcaption`, and the sanitizer's attributes plus `Attachment::ATTRIBUTES`.
- `sanitize_content_attachment` (line 19) is used by `Content#render_attachments` on the `content` attribute.
- **Sanitization happens at render time, not at store time.** The DB stores whatever the canonicalized form submission contained.

### 1.4 The editor abstraction (Rails main only)
Files: `AT/lib/action_text/editor.rb`, `editor/registry.rb`, `editor/configurator.rb`, `editor/trix_editor.rb`, `AT/app/helpers/action_text/tag_helper.rb`, `engine.rb:18-22,96-104`.
- Config: `config.action_text.editors = InheritableOptions.new(trix: {})` and `config.action_text.editor = :trix` (`engine.rb:19-22`).
- Initializer `"action_text.editors"` (`engine.rb:96-104`) runs `on_load(:action_text_rich_text)` and sets `RichText.editors = Editor::Registry.new(app.config.action_text.editors)` and `RichText.editor = editors.fetch(app.config.action_text.editor)`. It reads the config lazily, at the time RichText loads.
- `Editor::Registry#fetch(name)` (`registry.rb:10-23`) uses the `Configurator`. `Configurator#resolve` does `require "action_text/editor/#{name}_editor"` and then `Editor.const_get("#{Name}Editor")` (`configurator.rb:31-37`). That naming convention is **the reason Lexxy ships `lib/action_text/editor/lexxy_editor.rb`**: the file sits on `$LOAD_PATH` under the exact path Rails requires.
- `ActionText::Editor` base class (`editor.rb`):
  - `as_canonical(editable_fragment)` defaults to identity. It converts the editor's submitted HTML into stored form.
  - `as_editable(canonical_fragment)` defaults to identity. It converts stored form into what the editor loads.
  - `editor_name` is the demodulized class name minus "Editor", underscored (`LexxyEditor` becomes `"lexxy"`).
  - `editor_tag(options, &block)` returns `Editor::Tag.new(editor_name, options, &block)`.
- `Editor::Tag` (`editor.rb:55-76`):
  - `element_name` is `"#{editor_name}-editor"`, which gives **`<lexxy-editor>`**.
  - `render_in(view_context)` sets `class ||= "#{editor_name}-content"` (`lexxy-content`) and renders `content_tag(element_name, nil, options, &@block)`. There is **no hidden input**. `name` and `value` are ordinary attributes, and the block renders as child DOM.
- `Editor::TrixEditor` (`trix_editor.rb`):
  - `as_canonical` converts `figure[data-trix-attachment]` to `<action-text-attachment>`.
  - `as_editable` does the reverse.
  - Its `Tag#render_in` renders `hidden_field_tag(name, value, id: input)` followed by `<trix-editor input=...>`. When no value is given it captures the block as the value, which is the old contract.
- Helpers (`tag_helper.rb`):
  - `rich_textarea_tag(name, value, options, &block)` (line 35) sets `options[:value] ||= value.try(:to_editor_html) || value`, `data-direct-upload-url` (only if the route exists), and `data-blob-url-template = rails_service_blob_url(":signed_id", ":filename")`. It then calls **`render RichText.editor.editor_tag(options, &block)`**.
  - `Tags::ActionText#render` (line 57) calls `rich_textarea_tag(name, options.fetch("value") { value }, ...)`, where `value` is the `RichText` object.
  - `FormHelper#rich_textarea` and `FormBuilder#rich_textarea` (plus the `rich_text_area` aliases) delegate to it.
- History: the adapter is marked `:nodoc:` and has no CHANGELOG entry of its own on main. The main CHANGELOG has "Support block children in editor elements alongside value" (*Jorge Manrubia*, lines 27-48), which references #55827, where blocks were first introduced. Lexxy's detection comment points to **rails/rails#56926**. The CHANGELOG also has "Deprecate Trix-specific classes, modules, and methods", which covers `to_trix_content_attachment_partial_path`, `TrixConversion`, `to_trix_html` and `TrixAttachment` (*Sean Doyle*, lines 83-92). The rest of the 8.1 history is only referenced (`8-1-stable`). In practice the abstraction exists only on **Rails main / 8.2 alpha**. Rails 8.0/8.1 hardwire Trix in `rich_textarea_tag`.

### 1.5 Action Text and Active Storage JS
- `AT/app/javascript/actiontext/index.js`. Listens for `trix-initialize` (removes the attach button when there is no direct upload URL), `trix-file-accept`, and `trix-attachment-add`. For the last one it creates `new AttachmentUpload(attachment, target)`, calls `.start()`, then `attachment.setAttributes({sgid, url})`. **All of it is Trix-specific. Lexxy does not use it.**
- `AT/app/javascript/actiontext/attachment_upload.js`. Wraps `DirectUpload(file, element.dataset.directUploadUrl, this)`. It dispatches `direct-upload:*` events (initialize, start, before-blob-request, before-storage-request, progress with a simulated 90-99% phase, end, error). On completion it resolves `{ sgid: attributes.attachable_sgid, url: blobUrlTemplate.replace(":signed_id", ...).replace(":filename", ...) }`.
- `AS/direct_upload.js`. Runs `FileChecksum` (md5), then `BlobRecord`: a POST of `{blob:{filename, content_type, byte_size, checksum}}` to `direct_upload_url` with the CSRF token. The server responds with `blob.as_json` plus `direct_upload`. Then `BlobUpload` does a PUT to the service URL. Delegate hooks are `directUploadWillCreateBlobWithXHR` and `directUploadWillStoreFileWithXHR`. The callback receives `blob.toJSON()`, which contains the server's blob JSON **including `attachable_sgid`, `signed_id`, and any extra keys such as Lexxy's `previewable`/`url`**.

---

## 2. Lexxy's Ruby side, file by file

| File | What it does | Rails hook |
|---|---|---|
| `LX/lib/lexxy.rb` | `supports_alternative_text?` (`Attachment::ATTRIBUTES.include?("alt")`, lines 5-7). **`supports_editor_adapter?`** (lines 10-12) is true when `ActionText::Editor` is defined **and** `Editor#editor_tag` takes a `&block` param (the #56926 block-children change). `override_action_text_defaults` (lines 14-33) aliases `rich_textarea_tag`/`rich_text_area_tag`, `FormHelper#rich_textarea`, `FormBuilder#rich_textarea`, and `Tags::ActionText#render` to Lexxy's versions. It is only called on the legacy path. | alias_method monkey patches |
| `LX/lib/lexxy/engine.rb` | The Railtie. It branches on `supports_editor_adapter?`, described in the rows below. | see below |
| engine.rb:11-17 (Rails main) | Requires `lib/action_text/editor/lexxy_editor.rb`. Initializer `"lexxy.action_text_editor"`, `before: "action_text.editors"`, sets `app.config.action_text.editors[:lexxy] = {}` and `app.config.action_text.editor = :lexxy`. **This is the whole integration seam on Rails main.** | Editor registry config |
| engine.rb:18-37 (Rails 8.0/8.1) | Requires the `rich_text_area_tag`, `form_helper`, `form_builder` and `action_text_tag` modules. Sets `config.lexxy.override_action_text_defaults = true`. In `to_prepare` it prepends `Lexxy::TagHelper` into `ActionText::TagHelper`, `Lexxy::FormHelper` into `FormHelper`, `Lexxy::FormBuilder` into `FormBuilder`, and `Lexxy::ActionTextTag` into `Tags::ActionText`, then calls `Lexxy.override_action_text_defaults` if that option is set. Setting it to false keeps Trix as `rich_textarea` and exposes `lexxy_rich_textarea` side by side. | module prepend + aliases |
| engine.rb:39-43 | `ActionText::Attachable.singleton_class.prepend(Lexxy::Attachable)` runs in `to_prepare`. | wraps `Attachable.from_node` |
| engine.rb:45-50 | Adds `app/assets/stylesheets` and `app/javascript` to `config.assets.paths` when a pipeline exists. The built JS lives in `app/assets/javascript/lexxy.js` (gitignored and generated by rollup). As an engine `app/assets/*` dir, that folder is picked up automatically by propshaft/sprockets. `app/javascript` doesn't exist in the repo. | asset paths |
| engine.rb:52-62 | `on_load(:action_text_content)`: reads the **current** effective allowed tags and attributes (`Class.new.include(ContentHelper).new.sanitizer_allowed_tags`, i.e. `allowed_tags \|\| defaults`) and appends tags `video audio source embed table tbody tr th td` and attributes `controls poster data-language style value start`. It also does `Loofah::HTML5::SafeList::ALLOWED_CSS_FUNCTIONS << "var"`, so highlight `style="color: var(--highlight-1)"` survives. | ContentHelper mattrs, global Loofah list |
| engine.rb:64-68 | `on_load(:active_storage_blob) { prepend ActiveStorage::BlobWithPreviewUrl }`. | Blob#as_json |
| `LX/lib/action_text/editor/lexxy_editor.rb` | `Editor::LexxyEditor < Editor`. `editor_tag(...)` returns its own `Tag`. Its **`as_canonical`/`as_editable` are inherited identities**: Lexxy's wire format *is* the canonical `<action-text-attachment>` format. `Tag#render_in` (lines 11-17) adds `data-action-text-supports-alt` and **turns an `html_safe` value into a plain String** so `content_tag` escapes the attribute (Lexxy issue #749; otherwise `&lt;` in code blocks would decode). It then calls `super`, which renders `<lexxy-editor class="lexxy-content" name=... value=...>` with the block as children. | Editor adapter |
| `LX/lib/lexxy/rich_text_area_tag.rb` (legacy) | `Lexxy::TagHelper#lexxy_rich_textarea_tag`. It re-implements Rails main's behavior for 8.0/8.1. **It doesn't call `to_editor_html`**, because on 8.0/8.1 that would emit Trix `<figure>`s. Instead `render_custom_attachments_in` (lines 26-42) takes `value.body_before_type_cast` (the raw stored HTML). For every `<action-text-attachment>` **without `url`** (custom/sgid attachables such as mentions; blobs carry `url`), it renders `render_action_text_attachment(attachment)` into `node["content"]` **as JSON** (`.to_json`), and fills `content-type`. It then sets `name`, `value`, `class=lexxy-content`, `data-action-text-supports-alt`, `data-direct-upload-url`, and `data-blob-url-template`, and renders `content_tag("lexxy-editor", "", options, &block)`. The comment on line 25 reads "Temporary: we need to *adaptarize* action text". Note that the legacy path renders the content with **`to_attachable_partial_path`** (the show partial), while main uses `to_editor_content_attachment_partial_path`. | helper |
| `LX/lib/lexxy/form_helper.rb`, `form_builder.rb` | `lexxy_rich_textarea(_area)` builds `Tags::ActionText.new(..., &block).lexxy_render`. | helper |
| `LX/lib/lexxy/action_text_tag.rb` | Prepended into `Tags::ActionText`. `initialize` captures the block (8.0/8.1's `Tags::ActionText` didn't take one). `lexxy_render` (lines 9-16) is `add_default_name_and_id`, plus a leftover Trix-style `input` id (harmless), then `lexxy_rich_textarea_tag(name, value, ..., &@block)` wrapped in `error_wrapping`. | Tags::ActionText#render |
| `LX/lib/lexxy/attachable.rb` | Prepended onto `Attachable.from_node`. If the result is `MissingAttachable`, it tries `ActionText::Attachables::RemoteVideo.from_node(node)`. | attachable resolution |
| `LX/lib/action_text/attachables/remote_video.rb` | Mirrors `RemoteImage` for a `video/*` content type. It requires only that `url` is present, **with no absolute-URL check** (unlike main's RemoteImage). It stores url, content_type, width, height and filename, and defines `attachable_plain_text_representation` as `[caption \|\| filename \|\| "Video"]`. `to_partial_path` is `action_text/attachables/remote_video`. It doesn't define `attachable_markdown_representation`, so `to_markdown` falls back to the escaped caption. | new attachable |
| `LX/app/views/action_text/attachables/_remote_video.html.erb` | `<figure class="attachment attachment--preview attachment--video"><video controls width height><source src type>` plus an optional figcaption. `video`, `source` and `controls` are exactly what the sanitization initializer allows. | partial |
| `LX/app/views/action_text/attachables/_remote_image.html.erb` | Overrides Rails' partial to add `alt: remote_image.try(:alt)`. Engine views registered later are prepended ahead of ActionText's. | partial override |
| `LX/lib/active_storage/blob_with_preview_url.rb` | `as_json`: if `previewable?` (PDF, video and so on, via previewers, as opposed to variable images), it adds `"previewable" => true` and `"url"` = `rails_representation_path(preview(resize_to_limit: [1024,768]), only_path: true)` (this respects `script_name`; tests in `LX/test/actiontext/blob_test.rb`). The direct-upload JSON response then gives the editor a thumbnail URL for non-image previewables. | Blob#as_json |
| `LX/lib/tasks/actiontext/lexical_tasks.rake` | **An empty generator stub** (commented out). There is **no Trix→Lexxy migration task**. Because Lexxy stores canonical `<action-text-attachment>` HTML, which is the same as what Trix content is canonicalized to, no data migration is needed. | none |
| `LX/ext/Rakefile` | Gem native-extension hook (`spec.extensions`). When installed via `git:`, if `app/assets/javascript/lexxy.js` is missing it runs `yarn install --frozen-lockfile --ignore-scripts && yarn build`. | gem install |
| `LX/lib/lexxy/version.rb` | `VERSION = "1.0.0"`. The gemspec requires `railties >= 8.0.2`. | |
| `LX/app/assets/stylesheets/*.css` | `lexxy.css` (imports), `lexxy-editor.css`, `lexxy-content.css` (styles `.lexxy-content`), `lexxy-variables.css`. | |
| `LX/config/ci.rb` | The `bin/ci` script. | |

Notes:
- There is **no importmap config in the gem**. The host pins it manually (`home/docs/index.md:29-31`): `pin "lexxy", to: "lexxy.js"` and `pin "@rails/activestorage", to: "activestorage.esm.js"`. The npm package `@37signals/lexxy` builds to `dist/` for bundlers.
- `isolate_namespace Lexxy` is set, but the engine has no routes.
- Rails version support: the gemspec requires `>= 8.0.2`. The Gemfile switches on `USE_RAILS_WITHOUT_ACTION_TEXT_ADAPTER=true` (Rails `~> 8.1.0`, with json pinned below 3) versus `rails/rails main`. CI runs both variants (`.github/workflows/ci.yml:88-105`, `matrix.use_legacy_rails`). `LX/test/helpers/lexxy/tag_helper_test.rb` skips when the adapter is present.
- Sanitizer composition caveat: Lexxy's `on_load(:action_text_content)` *appends to whatever `allowed_tags` is at that moment*. The dummy app sets `ContentHelper.allowed_tags` in `to_prepare` (`LX/test/dummy/config/initializers/action_text.rb`), adding `bc-mention` and `gid`. If a host app *assigns* the allowlists after `Content` has loaded (for example with eager loading), Lexxy's additions are overwritten. The result depends on load order.
- Editor selection: Lexxy sets `config.action_text.editor = :lexxy` in an engine initializer. Rails reads it lazily in `on_load(:action_text_rich_text)`, so a host can still override it (for example to `:trix`) in `config/initializers`, before RichText loads. The dummy app shows how to handle mixed Trix and Lexxy content: `TrixPostsController#canonicalize_trix_body` manually runs `TrixEditor.new.as_canonical`, and `ApplicationHelper#to_trix_html` runs `TrixEditor#as_editable`, because the global editor is Lexxy.

---

## 3. Lexxy's JS side of the seam (only what touches Action Text)
- `<lexxy-editor>` is a **form-associated custom element** (`static formAssociated = true`, `LX/src/elements/editor.js:54`, `attachInternals()` at line 77). It **submits through `ElementInternals.setFormValue(html)`** (`editor.js:582-590`) under its `name` attribute. There is no hidden input, which is why the Rails-main base `Editor::Tag` doesn't render one.
- Initial load: `#loadInitialValue` reads `valueBeforeDisconnect || getAttribute("value") || "<p><br></p>"` (`editor.js` around line 592). `value` getter = DOMPurify-sanitized `$generateHtmlFromNodes` (`editor.js:361-395`).
- Upload config comes from `data-direct-upload-url` and `data-blob-url-template` (`editor.js:234-240`, set by Rails' `rich_textarea_tag` or Lexxy's legacy helper), and `data-action-text-supports-alt` (read in `elements/attachment_toolbar.js:196`).
- Uploads: `ActionTextAttachmentUploadNode` does a dynamic `import("@rails/activestorage")` and runs `new DirectUpload(file, uploadUrl, delegate)` (`nodes/action_text_attachment_upload_node.js:149-175`). It dispatches `lexxy:upload-start`/`-progress`/`-end` rather than `direct-upload:*`. On success, `toAttachmentNode()` (lines 259-289) maps blob JSON to node properties:
  - `sgid` from `attachable_sgid`
  - `contentType`, `fileName`, `fileSize`, `previewable` (Lexxy's `as_json` addition)
  - `src`: `blob.url` (the preview representation) if previewable, otherwise `blobUrlTemplate` with `signed_id`/`filename` substituted
  - `previewStatusUrl` from `blob.preview_status_url`. The gem doesn't provide this; it's host-app territory.
- Serialization to HTML:
  - `ActionTextAttachmentNode.exportDOM` (`nodes/action_text_attachment_node.js:160-175`) emits `<action-text-attachment sgid previewable url alt caption content-type filename filesize width height presentation="gallery">`.
  - `ImageGalleryNode.exportDOM` emits `<div class="attachment-gallery attachment-gallery--N">`, so the server's `AttachmentGallery` selector matches it.
  - `CustomActionTextAttachmentNode.exportDOM` (`nodes/custom_action_text_attachment_node.js:139-146`) emits `<action-text-attachment sgid content="<raw inner html>" content-type>`.
- Import:
  - Custom attachment import requires a `content` attribute (`custom_action_text_attachment_node.js:22-25`) and parses it with `parseAttachmentContent`, which tries `JSON.parse` first and falls back to raw HTML (`helpers/storage_helper.js:13-20`). That fallback bridges the legacy path's JSON-encoded content and main's raw-HTML content.
  - `ActionTextAttachmentNode.importDOM` reads `sgid`, `url`, `previewable`, `alt`, `caption`, `content-type` and the other attributes, and also accepts bare `<img>`/`<video>`.
- Tag name and namespace: `Lexxy.configure({ global: { attachmentTagName, attachmentContentTypeNamespace } })` (`src/config/lexxy.js:3-8`, defaults `action-text-attachment` and `actiontext`). These must match `config.action_text.attachment_tag_name` on the server; nothing syncs them automatically. The default prompt content type is `application/vnd.actiontext.<prompt name>` (`elements/prompt.js:533-536`).
- Prompts and mentions (`elements/prompt.js:489-540`): each `<lexxy-prompt-item sgid="...">` has a `<template type="editor">`. Its innerHTML becomes a `CustomActionTextAttachmentNode({sgid, contentType, innerHtml})`. The server supplies the sgid through `person.attachable_sgid` (`LX/test/dummy/app/views/people/_prompt_item.html.erb`). With `insert-editable-text`, the template is inserted as ordinary nodes instead of an attachment.
- Client allowlist for attachment attributes: `ATTACHMENT_ATTRIBUTES` in `extensions/attachments_extension.js:15-16`.

---

## 4. End-to-end data flow

### Rails main (adapter path)
1. **Form render.** `form.rich_text_area :body do <lexxy-prompt>…</lexxy-prompt> end` → `FormBuilder#rich_textarea` → `FormHelper#rich_textarea` → `Tags::ActionText#render` (`AT tag_helper.rb:57`, `value` = `post.body` RichText) → `rich_textarea_tag` (`tag_helper.rb:35`).
   - `options[:value] = rich_text.to_editor_html`, which calls `Content#to_editor_html`, which runs `render_attachments(&:to_editor_attachment)`. For each `<action-text-attachment>`: the existing `content` is sanitized, `Attachment.from_node` resolves the attachable by sgid, and `with_full_attributes` merges in `to_rich_text_attributes` (sgid, content-type, filename, filesize, width, height, previewable). Then `to_editor_attachment!` renders `to_editor_content_attachment_partial_path` into `node["content"]` as raw HTML. Blobs return nil there, so they get no content. A `Person` falls back to `to_partial_path`, i.e. `people/_person`. Finally `LexxyEditor#as_editable` is the identity.
   - The helper adds data `direct-upload-url` and `blob-url-template`, then calls `render LexxyEditor#editor_tag`. `LexxyEditor::Tag#render_in` adds `data-action-text-supports-alt` and un-`html_safe`s the value. Base `Tag#render_in` produces `<lexxy-editor class="lexxy-content" name="post[body]" id="post_body" value="…escaped HTML…" data-…><lexxy-prompt …/></lexxy-editor>`.
2. **Editor load.** The custom element connects and parses the `value` attribute through `$generateNodesFromDOM`:
   - `<action-text-attachment>` with a `content` attribute becomes a `CustomActionTextAttachmentNode`. Its inner HTML is re-sanitized with DOMPurify SAFE_FOR_XML.
   - One with `sgid`/`url` becomes an `ActionTextAttachmentNode`.
   - Gallery divs become an `ImageGalleryNode`.
   - The initial form value is set via `internals.setFormValue`.
3. **User edits and uploads.** A file drop or paste creates an upload node. `DirectUpload` POSTs to `/rails/active_storage/direct_uploads`, and the response is `blob.as_json` with `attachable_sgid`, `signed_id`, and `previewable`/`url` from `BlobWithPreviewUrl`. The file is PUT to the service, and the node becomes an `ActionTextAttachmentNode` with the sgid and a blob or preview URL. A mention from a prompt becomes a `CustomActionTextAttachmentNode` with the sgid and the template HTML.
4. **Form submit.** On every update the element sets its form value to the sanitized `$generateHtmlFromNodes` output, e.g. `<p>Hi <action-text-attachment sgid="…" content-type="application/vnd.actiontext.mention" content="&lt;span …&gt;"></action-text-attachment></p><div class="attachment-gallery …"><action-text-attachment sgid url filename … presentation="gallery"></action-text-attachment>…</div>`. It's posted as `post[body]`, which the `FormData` spec includes for form-associated elements.
5. **Server store.** `post.update(body: html)` → `rich_text_body.body = html`. The `Content` coder runs `Content.new(html)`, which calls `LexxyEditor#as_canonical` (identity), minifies attachments (empties inner HTML while **keeping attributes including `content` and `url`**), canonicalizes galleries (bare `<div>`), and unwraps markdown tags. `before_validation` sets `embeds` = the blob attachables. The HTML is stored in `action_text_rich_texts.body`. **No server-side sanitization happens at this step.**
6. **Show page.** `<%= @post.body %>` → `RichText#to_s` → `Content#to_s` → the layout `<div class="trix-content">` around `render_action_text_content`:
   - Each attachment node's inner HTML is filled by `render_action_text_attachment`, using `to_attachable_partial_path`:
     - Blob: `active_storage/blobs/_blob` (`<figure>` with representation `<img>`)
     - Person: `people/_person`
     - Sgid-less `video/*` with `url`: Lexxy's `RemoteVideo`, rendered by `_remote_video`
     - Sgid-less absolute-URL image: `RemoteImage`
     - Anything else: `MissingAttachable` "☒"
   - Galleries are wrapped in `_attachment_gallery`.
   - The full HTML then goes through rails-html-sanitizer with the allowlists as extended by Lexxy.
   - Separately, Lexxy's JS `highlightCode()` runs on the rendered view (per AGENTS.md).
7. **Re-edit.** Step 1 again. `to_editor_html` re-renders the `content` for custom attachables from the *current* record through `to_editor_content_attachment_partial_path`, so a renamed Person shows the new name, and re-hydrates blob attributes from the Blob.

### Rails 8.0/8.1 (legacy path)
The flow is the same except for these points:
- In step 1, the monkey-patched `rich_textarea` runs `Lexxy::ActionTextTag#lexxy_render` → `lexxy_rich_textarea_tag`. It uses `body_before_type_cast` (raw stored HTML), without `to_editor_html` or full-attribute merging. Only sgid attachments **without `url`** get `content` filled, **JSON-encoded**, from `render_action_text_attachment`, i.e. the *show* partial (`to_attachable_partial_path`).
- In step 5, 8.0/8.1's `Content.new` runs `fragment_by_converting_trix_attachments`, which is a no-op for Lexxy's already-canonical HTML.
- `Attachment::ATTRIBUTES` lacks `alt`, so `data-action-text-supports-alt="false"` and the JS hides alt-text UI. (Alt would otherwise be dropped by the server's attribute slicing and the sanitizer.)

### Where each layer can strip markup (per AGENTS.md)
1. DOMPurify on the client, in the `value` getter and in custom attachment `createDOM` with SAFE_FOR_XML.
2. `Attachment::ATTRIBUTES` slicing, which applies only to nodes built via `from_attributes`/`with_full_attributes` (for example at edit time).
3. `sanitize_content_attachment` on `content` attributes during `render_attachments`, at both edit and show time.
4. Loofah/rails-html-sanitizer on show, which is why Lexxy extends the tags, attributes and CSS `var()`.
5. `highlightCode()` in the rendered view.

---

## 5. Tests that exercise the round trip
- `LX/test/system/mention_round_trip_test.rb`: edit, then save, then show (asserts `action-text-attachment[sgid][content-type=…mention] bc-mention[gid]`), then re-edit (asserts that the editor value's `content` contains `bc-mention`).
- `LX/test/system/attachments/*_round_trip_test.rb` cover alt, caption, content, content images, tag name (a poisoned `tagName` in a Lexical paste payload) and url. `gallery_test.rb` and `action_text_load_test.rb` load pre-built canonical HTML, including mixed previewable galleries.
- `LX/test/system/trix/from_trix_to_lexxy_test.rb` and `from_lexxy_to_trix_test.rb` test cross-editor compatibility using the dummy's `TrixPostsController` and `ApplicationHelper#to_trix_html`.
- `LX/test/helpers/action_text_tag_test.rb` checks that the helper emits `lexxy-editor` or `trix-editor` and the field name, both with and without a block. `LX/test/helpers/lexxy/tag_helper_test.rb` covers the legacy path only: JSON `content` for mentions and entity preservation in `value`.
- `LX/test/actiontext/blob_test.rb` covers `BlobWithPreviewUrl`. `image_attributes_test.rb` is also in that folder.
- Dummy app pieces:
  - `Post has_rich_text :body`
  - `Person include ActionText::Attachable`, with `content_type` `application/vnd.actiontext.mention` and partial `people/_person` emitting `<bc-mention gid>`
  - The allowlist initializer (`bc-mention`, `gid`)
  - The importmap pins
  - Posts `_form` using `form.rich_text_area :body … do <lexxy-prompt>… end`
