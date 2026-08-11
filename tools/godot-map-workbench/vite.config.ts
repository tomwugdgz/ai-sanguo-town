import react from "@vitejs/plugin-react";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";
import { createLocalMapWorkbenchPlugin } from "./src/dev-server/localMapWorkbench";

const workbenchRoot = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(workbenchRoot, "../..");

export default defineConfig({
  plugins: [react(), createLocalMapWorkbenchPlugin({ repoRoot })],
  server: {
    host: "127.0.0.1",
    port: 5175,
    fs: {
      allow: [repoRoot, workbenchRoot]
    }
  },
  test: {
    environment: "jsdom",
    setupFiles: "./vitest.setup.ts"
  }
});
