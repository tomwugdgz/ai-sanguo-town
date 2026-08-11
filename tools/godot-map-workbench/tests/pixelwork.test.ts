import { describe, expect, it } from "vitest";
import { importPixelworkPackage, type PixelworkManifest } from "../src/importers/pixelwork";

describe("Pixelwork importer", () => {
  it("imports tile images at their manifest pixel positions", () => {
    const manifest: PixelworkManifest = {
      version: 1,
      format: "pixelwork_map_stitch",
      resource_root: "world/maps/demo",
      scene_file: "demo_map.tscn",
      annotations_file: "demo_annotations.json",
      coordinate_system: "godot_2d_pixels",
      canvas: { width: 300, height: 200 },
      layers: [
        {
          id: "overall",
          label: "整体",
          folder: "overall",
          visible: true,
          order: 0,
          tiles: [
            {
              key: "tile_0_0",
              name: "tile 0,0",
              layer: "overall",
              layer_label: "整体",
              image: "tiles/overall_0_0.png",
              mime_type: "image/png",
              guid: "a",
              pixel: { x: 0, y: 0, width: 100, height: 80 }
            },
            {
              key: "tile_1_0",
              name: "tile 1,0",
              layer: "overall",
              layer_label: "整体",
              image: "tiles/overall_1_0.png",
              mime_type: "image/png",
              guid: "b",
              pixel: { x: 100, y: 0, width: 100, height: 80 }
            }
          ]
        },
        {
          id: "object",
          label: "物件",
          folder: "object",
          visible: true,
          order: 20,
          tiles: [
            {
              key: "object_0_1",
              name: "object 0,1",
              layer: "object",
              layer_label: "物件",
              image: "tiles/object_0_1.png",
              mime_type: "image/png",
              guid: "c",
              pixel: { x: 0, y: 80, width: 100, height: 80 }
            }
          ]
        }
      ]
    };

    const document = importPixelworkPackage({
      mapId: "demo_map",
      displayName: "Demo Map",
      manifest,
      packageRoot: "game/world/maps/demo_map/source/pixelwork_map_stitch/latest"
    });

    expect(document.canvas).toMatchObject({ width: 300, height: 200, unit: "pixel" });
    expect(document.source.godotManifest).toBe("game/world/maps/demo_map/source/pixelwork_map_stitch/latest/demo_map_godot.json");
    expect(document.layers.images).toHaveLength(3);
    expect(document.layers.images.map((image) => [image.id, image.position.x, image.position.y, image.size.width])).toEqual([
      ["img_object_object_0_1", 0, 80, 100],
      ["img_overall_tile_0_0", 0, 0, 100],
      ["img_overall_tile_1_0", 100, 0, 100]
    ]);
    expect(document.layers.images.find((image) => image.id === "img_object_object_0_1")?.kind).toBe("object");
  });

  it("imports Pixelwork annotation shapes into runtime layers", () => {
    const manifest: PixelworkManifest = {
      version: 1,
      format: "pixelwork_map_stitch",
      resource_root: "world/maps/demo",
      scene_file: "demo_map.tscn",
      annotations_file: "demo_annotations.json",
      canvas: { width: 200, height: 200 },
      layers: []
    };

    const document = importPixelworkPackage({
      mapId: "demo_map",
      manifest,
      packageRoot: "game/world/maps/demo",
      annotations: {
        version: 1,
        layers: [
          {
            id: "collision",
            label: "碰撞",
            color: "#ff0000",
            shapes: [{ id: "wall", rect: { x: 10, y: 20, width: 30, height: 40 } }]
          },
          {
            id: "top",
            label: "遮挡",
            order: 120,
            shapes: [{ id: "roof", polygon: [{ x: 0, y: 0 }, { x: 50, y: 0 }, { x: 50, y: 30 }] }]
          },
          {
            id: "adjust",
            label: "修正",
            shapes: [{ id: "hit", points: [{ x: 5, y: 5 }, { x: 25, y: 5 }, { x: 25, y: 25 }] }]
          }
        ]
      }
    });

    expect(document.layers.collision[0]).toMatchObject({ id: "wall", debugColor: "#ff0000" });
    expect(document.layers.collision[0].shape.points).toEqual([
      { x: 10, y: 20 },
      { x: 40, y: 20 },
      { x: 40, y: 60 },
      { x: 10, y: 60 }
    ]);
    expect(document.layers.occlusion[0]).toMatchObject({ id: "roof", baselineY: 30, zIndex: 120 });
    expect(document.layers.interactions[0]).toMatchObject({ id: "hit", primaryAction: "inspect" });
  });
});
