import { defineConfig } from "vite"
import { resolve } from "node:path"

// Builds the editor for the Rails prototype into its public/editor directory.
export default defineConfig({
  build: {
    outDir: resolve(import.meta.dirname, "../provenance-rails/public/editor"),
    emptyOutDir: true,
    lib: { entry: resolve(import.meta.dirname, "rails/editor_entry.js"), formats: [ "es" ], fileName: () => "editor.js" }
  }
})
