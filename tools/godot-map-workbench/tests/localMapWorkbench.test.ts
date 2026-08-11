import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { importGodotPrototypeScene, resolveWorkbenchAssetPath, saveAndSyncMap } from "../src/dev-server/localMapWorkbench";
import { createEmptyMapDocument, polygonAround } from "../src/model/mapDocument";

describe("local map workbench save pipeline", () => {
  let repoRoot = "";

  beforeEach(async () => {
    repoRoot = await fs.mkdtemp(path.join(os.tmpdir(), "godot-map-workbench-"));
  });

  afterEach(async () => {
    if (repoRoot) {
      await fs.rm(repoRoot, { recursive: true, force: true });
    }
  });

  it("saves map_tool.json and immediately syncs Godot runtime files", async () => {
    const document = createSaveDocument();
    const result = await saveAndSyncMap({ repoRoot, document, expectedHash: "" });

    expect(result.hash).toHaveLength(64);
    expect(Object.keys(result.paths).sort()).toEqual([
      "animation.json",
      "audio.json",
      "camera.json",
      "collision.json",
      "effects.json",
      "interaction.json",
      "layers.tscn",
      "lighting.json",
      "map_tool.json",
      "navigation.json",
      "occlusion.json",
      "runtime.json",
      "semantic.json"
    ]);

    for (const relativePath of Object.values(result.paths)) {
      expect(relativePath.startsWith("game/world/maps/save_test/generated/")).toBe(true);
      await expect(fs.stat(path.join(repoRoot, relativePath))).resolves.toBeTruthy();
    }

    const tscn = await fs.readFile(path.join(repoRoot, result.paths["layers.tscn"]), "utf8");
    expect(tscn).toContain('[node name="MapRuntimeLayers" type="Node2D"]');
    expect(tscn).toContain('[node name="nav_walkable_merged" type="Polygon2D" parent="NavigationDebug"]');
    expect(tscn).toContain('[node name="Wall" type="CollisionPolygon2D" parent="Collision/WorldBlockCollision"]');
    expect(tscn).toContain('[node name="RoofMask" type="Polygon2D" parent="Occlusion"]');
    expect(tscn).toContain("metadata/baseline_y = 80");
  });

  it("rejects stale expectedHash unless force is explicit", async () => {
    const document = createSaveDocument();
    await saveAndSyncMap({ repoRoot, document, expectedHash: "" });

    await expect(saveAndSyncMap({ repoRoot, document, expectedHash: "" })).rejects.toThrow("磁盘文件已变化");
    await expect(saveAndSyncMap({ repoRoot, document, expectedHash: "", force: true })).resolves.toMatchObject({ ok: true });
  });

  it("rejects unsafe map ids before writing files", async () => {
    const document = createEmptyMapDocument("../escape");

    await expect(saveAndSyncMap({ repoRoot, document, expectedHash: "" })).rejects.toThrow("mapId");
    await expect(fs.stat(path.join(repoRoot, "game"))).rejects.toThrow();
  });

  it("imports an indoor Godot scene directly from Sprite2D and CollisionShape2D data", async () => {
    const sceneDir = path.join(repoRoot, "game/world/prototypes/town_hd_expansion_demo");
    const assetDir = path.join(sceneDir, "assets");
    await fs.mkdir(assetDir, { recursive: true });
    await fs.writeFile(path.join(assetDir, "indoor_cafe_shell_v1.png"), pngHeader(100, 80));
    await fs.writeFile(path.join(sceneDir, "IndoorCafe.tscn"), `[gd_scene format=3]

[ext_resource type="Texture2D" path="res://world/prototypes/town_hd_expansion_demo/assets/indoor_cafe_shell_v1.png" id="1_room_shell"]

[sub_resource type="RectangleShape2D" id="RectangleShape2D_top_main"]
size = Vector2(20, 10)

[node name="IndoorCafe" type="Node2D"]

[node name="RoomShell" type="Sprite2D" parent="."]
texture = ExtResource("1_room_shell")

[node name="WallCollision" type="StaticBody2D" parent="."]

[node name="TopMain" type="CollisionShape2D" parent="WallCollision"]
position = Vector2(0, 0)
shape = SubResource("RectangleShape2D_top_main")

[node name="IndoorEntryPoint" type="Marker2D" parent="."]
position = Vector2(10, 5)
`, "utf8");

    const document = await importGodotPrototypeScene(
      repoRoot,
      "town_hd_expansion_demo_indoor_cafe",
      "game/world/prototypes/town_hd_expansion_demo/IndoorCafe.tscn"
    );

    expect(document.canvas).toEqual({ width: 100, height: 80, defaultGridSize: 24, unit: "pixel" });
    expect(document.layers.images[0]).toMatchObject({
      asset: "game/world/prototypes/town_hd_expansion_demo/assets/indoor_cafe_shell_v1.png",
      position: { x: 0, y: 0 },
      size: { width: 100, height: 80 }
    });
    expect(document.layers.collision[0].shape.points).toEqual([
      { x: 40, y: 35 },
      { x: 60, y: 35 },
      { x: 60, y: 45 },
      { x: 40, y: 45 }
    ]);
    expect(document.layers.points[0]).toMatchObject({
      id: "IndoorEntryPoint",
      position: { x: 60, y: 45 }
    });
  });

  it("only serves media assets from map-related paths", async () => {
    await fs.mkdir(path.join(repoRoot, "game/world/prototypes/town_hd_expansion_demo/assets"), { recursive: true });
    await fs.mkdir(path.join(repoRoot, "docs"), { recursive: true });
    await fs.writeFile(path.join(repoRoot, "game/world/prototypes/town_hd_expansion_demo/assets/room.png"), pngHeader(16, 16));
    await fs.writeFile(path.join(repoRoot, "game/world/prototypes/town_hd_expansion_demo/IndoorCafe.tscn"), "[gd_scene format=3]");
    await fs.writeFile(path.join(repoRoot, "AGENTS.md"), "secret", "utf8");
    await fs.writeFile(path.join(repoRoot, "docs/preview.png"), pngHeader(16, 16));

    expect(resolveWorkbenchAssetPath(repoRoot, "game/world/prototypes/town_hd_expansion_demo/assets/room.png"))
      .toBe(path.join(repoRoot, "game/world/prototypes/town_hd_expansion_demo/assets/room.png"));
    expect(() => resolveWorkbenchAssetPath(repoRoot, "AGENTS.md")).toThrow("媒体资源");
    expect(() => resolveWorkbenchAssetPath(repoRoot, "docs/preview.png")).toThrow("媒体资源");
    expect(() => resolveWorkbenchAssetPath(repoRoot, "game/assets/../../docs/preview.png")).toThrow("媒体资源");
    expect(() => resolveWorkbenchAssetPath(repoRoot, "game/world/prototypes/town_hd_expansion_demo/IndoorCafe.tscn")).toThrow("图片或音频");
  });
});

function createSaveDocument() {
  const document = createEmptyMapDocument("save_test", "Save Test", 120, 120);
  document.layers.navigation.regions.push({
    id: "WalkableRegion",
    name: "Walkable Region",
    type: "walkable",
    shape: polygonAround({ x: 60, y: 60 }, 42),
    debugColor: "#22c55e",
    enabled: true
  });
  document.layers.collision.push({
    id: "Wall",
    name: "Wall",
    kind: "world",
    shape: polygonAround({ x: 60, y: 60 }, 24),
    collisionLayer: 2,
    collisionMask: 0,
    debugColor: "#ef4444",
    enabled: true
  });
  document.layers.interactions.push({
    id: "Hit",
    name: "Hit",
    type: "debug",
    targetId: "Wall",
    primaryAction: "inspect",
    shape: { type: "circle", x: 60, y: 60, radius: 32 },
    tags: ["debug"],
    enabled: true
  });
  document.layers.occlusion.push({
    id: "RoofMask",
    name: "Roof Mask",
    shape: polygonAround({ x: 60, y: 40 }, 24),
    baselineY: 80,
    sortMode: "foot_y",
    zIndex: 120,
    debugColor: "#8b5cf6",
    enabled: true
  });
  document.layers.lighting.push({
    id: "Lamp",
    name: "Lamp",
    type: "point",
    position: { x: 80, y: 60 },
    color: "#ffd37a",
    energy: 1,
    radius: 180,
    zIndex: 20,
    timeRules: [],
    weatherRules: [],
    enabled: true
  });
  return document;
}

function pngHeader(width: number, height: number): Buffer {
  const buffer = Buffer.alloc(24);
  buffer[0] = 0x89;
  buffer.write("PNG", 1, "ascii");
  buffer.writeUInt32BE(width, 16);
  buffer.writeUInt32BE(height, 20);
  return buffer;
}
