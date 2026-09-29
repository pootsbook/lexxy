import { defineConfig } from "@playwright/test"

// End-to-end against the Rails prototype: `npm run test:rails`. Builds the
// editor bundle, resets the development database with the sample import, and
// boots the server on port 3179.
export default defineConfig({
  testDir: "browser-rails",
  testMatch: "**/*.pw.js",
  workers: 1,
  use: {
    baseURL: "http://localhost:3179",
    launchOptions: { executablePath: process.env.CHROMIUM_PATH || "/opt/pw-browsers/chromium" }
  },
  webServer: {
    command: "npm run build:rails && cd ../provenance-rails && bin/rails db:reset && bin/rails server -p 3179",
    url: "http://localhost:3179/up",
    reuseExistingServer: false,
    timeout: 120_000
  }
})
