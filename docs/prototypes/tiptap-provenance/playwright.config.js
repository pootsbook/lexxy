import { defineConfig } from "@playwright/test"

export default defineConfig({
  testDir: "browser",
  testMatch: "**/*.pw.js",
  use: {
    baseURL: "http://localhost:5179",
    launchOptions: { executablePath: process.env.CHROMIUM_PATH || "/opt/pw-browsers/chromium" }
  },
  webServer: {
    command: "npx vite demo --port 5179 --strictPort",
    url: "http://localhost:5179",
    reuseExistingServer: true
  }
})
