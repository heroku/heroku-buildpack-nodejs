import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    testTimeout: 60000,
    hookTimeout: 60000,
    exclude: ['tmp/**', 'tests/fixtures/**', 'node_modules/**']
  }
})
