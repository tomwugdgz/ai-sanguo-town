import fs from "node:fs/promises";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { importPixelworkPackage, type PixelworkAnnotations, type PixelworkManifest } from "../src/importers/pixelwork";

const PIXELWORK_PACKAGE_ROOT =
  "game/world/maps/pixelwork_map_stitch/2026-07-08T07-57-31-361Z_20260708_161838_873";

describe("current Pixelwork package integration", () => {
  it("imports the current Pixelwork canvas and tile coordinates without flattening images", async () => {
    const repoRoot = path.resolve(process.cwd(), "../..");
    const packageRootPath = path.join(repoRoot, PIXELWORK_PACKAGE_ROOT);
    let entries: string[];
    try {
      entries = await fs.readdir(packageRootPath);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") {
        return;
      }
      throw error;
    }
    const manifestName = entries.find((entry) => entry.endsWith("_godot.json"));
    expect(manifestName).toBeTruthy();

    const manifest = JSON.parse(await fs.readFile(path.join(packageRootPath, manifestName as string), "utf8")) as PixelworkManifest;
    const annotations = manifest.annotations_file
      ? JSON.parse(await fs.readFile(path.join(packageRootPath, manifest.annotations_file), "utf8")) as PixelworkAnnotations
      : undefined;
    const document = importPixelworkPackage({
      mapId: "pixelwork_current",
      displayName: "Pixelwork Current",
      manifest,
      annotations,
      packageRoot: PIXELWORK_PACKAGE_ROOT
    });

    const expectedTileCount = manifest.layers.reduce((sum, layer) => sum + layer.tiles.length, 0);
    const firstTileLayer = manifest.layers.find((layer) => layer.tiles.length > 0);
    const firstTile = firstTileLayer?.tiles[0];

    expect(document.canvas.width).toBe(manifest.canvas.width);
    expect(document.canvas.height).toBe(manifest.canvas.height);
    expect(document.layers.images).toHaveLength(expectedTileCount);
    for (const layer of manifest.layers) {
      for (const tile of layer.tiles) {
        expect(document.layers.images.some((image) => image.asset.endsWith(tile.image))).toBe(true);
      }
    }
    expect(document.layers.images.some((image) => image.size.width === manifest.canvas.width && image.size.height === manifest.canvas.height)).toBe(false);

    expect(firstTileLayer).toBeTruthy();
    expect(firstTile).toBeTruthy();
    const importedFirstTile = document.layers.images.find((image) => (
      image.sourceLayerId === firstTileLayer?.id &&
      image.tileKey === firstTile?.key
    ));
    expect(importedFirstTile).toMatchObject({
      position: firstTile?.pixel ? { x: firstTile.pixel.x, y: firstTile.pixel.y } : undefined,
      size: firstTile?.pixel ? { width: firstTile.pixel.width, height: firstTile.pixel.height } : undefined
    });
  });
});
