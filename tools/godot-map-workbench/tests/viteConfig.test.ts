import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

describe("vite config", () => {
  it("binds the dev server to localhost only", async () => {
    const config = await fs.readFile(path.join(root, "vite.config.ts"), "utf8");
    expect(config).toContain('host: "127.0.0.1"');
    expect(config).toContain("port: 5175");
    expect(config).not.toContain("host: true");
  });
});
