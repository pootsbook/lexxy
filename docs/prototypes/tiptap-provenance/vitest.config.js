import { defineConfig } from "vitest/config"

// Test files use a .check.js suffix so the Lexxy repo's own `yarn test`
// (which globs **/*.test.js) never picks this prototype up.
export default defineConfig({
  test: {
    environment: "jsdom",
    include: [ "test/**/*.check.js" ]
  }
})
