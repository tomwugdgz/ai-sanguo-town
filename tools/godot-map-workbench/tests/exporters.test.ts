import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { exportSplitRuntimeFiles } from "../src/exporters/runtime";
import { exportLayersTscn } from "../src/exporters/tscn";
import { stableJson } from "../src/model/hash";
import { createEmptyMapDocument, paintCells, polygonAround } from "../src/model/mapDocument";
import type { MapToolDocument } from "../src/model/types";

describe("runtime exporters", () => {
  it("exports split runtime files for every runtime domain", () => {
    const document = makeRuntimeDocument();
    const splitFiles = exportSplitRuntimeFiles(document);

    expect(Object.keys(splitFiles).sort()).toEqual([
      "animation.json",
      "audio.json",
      "camera.json",
      "collision.json",
      "effects.json",
      "interaction.json",
      "lighting.json",
      "navigation.json",
      "occlusion.json",
      "runtime.json",
      "semantic.json"
    ]);
    expect(splitFiles["runtime.json"].layers.lighting).toHaveLength(1);
    expect(splitFiles["navigation.json"].cells).toEqual([{ x: 1, y: 1, type: "walkable" }]);
    expect(splitFiles["navigation.json"].regions).toHaveLength(1);
  });

  it("generates a Godot scene with declared resources before nodes", () => {
    const tscn = exportLayersTscn(makeRuntimeDocument());

    expect(tscn).toContain('[node name="MapRuntimeLayers" type="Node2D"]');
    expect(tscn).toContain('[node name="nav_walkable_merged" type="Polygon2D" parent="NavigationDebug"]');
    expect(tscn).toContain('[node name="WorldBlockCollision" type="StaticBody2D" parent="Collision"]');
    expect(tscn).toContain('[node name="Wall" type="CollisionPolygon2D" parent="Collision/WorldBlockCollision"]');
    expect(tscn).toContain('[node name="Roof" type="Polygon2D" parent="Occlusion"]');
    expect(tscn).toContain('script = ExtResource("res_1")');
    expect(tscn).toContain('texture = ExtResource("res_2")');
    expect(tscn).toContain("metadata/baseline_y = 90");
    expect(tscn).toContain('metadata/activation_mode = "foot_inside"');
    expect(tscn).toContain('[node name="Lamp" type="PointLight2D" parent="Lighting"]');
    expect(tscn).toContain('[node name="Glow" type="GPUParticles2D" parent="Effects"]');
    expect(tscn).toContain('[node name="RiverSound" type="AudioStreamPlayer2D" parent="Audio"]');
    expect(tscn).toContain('[node name="CameraFocus" type="Marker2D" parent="CameraZones"]');

    const firstSubResource = tscn.indexOf("[sub_resource");
    const firstNode = tscn.indexOf("[node");
    expect(firstSubResource).toBeGreaterThan(0);
    expect(firstSubResource).toBeLessThan(firstNode);
  });

  it("reproduces the committed town navigation outputs byte-for-byte", () => {
    const repositoryRoot = resolve(process.cwd(), "../..");
    const generatedDirectory = resolve(repositoryRoot, "game/world/maps/town/generated");
    const document = JSON.parse(
      readFileSync(resolve(generatedDirectory, "map_tool.json"), "utf8")
    ) as MapToolDocument;
    const splitFiles = exportSplitRuntimeFiles(document);

    expect(stableJson(splitFiles["navigation.json"])).toBe(
      readFileSync(resolve(generatedDirectory, "navigation.json"), "utf8")
    );
    expect(stableJson(splitFiles["runtime.json"])).toBe(
      readFileSync(resolve(generatedDirectory, "runtime.json"), "utf8")
    );
    expect(exportLayersTscn(document)).toBe(
      readFileSync(resolve(generatedDirectory, "layers.tscn"), "utf8")
    );
  });
});

function makeRuntimeDocument() {
  const document = createEmptyMapDocument("town_runtime", "Town Runtime", 240, 240);
  document.layers.images.push({
    id: "BaseTile",
    name: "Base Tile",
    asset: "game/world/maps/town_runtime/images/base.png",
    kind: "base",
    position: { x: 0, y: 0 },
    size: { width: 240, height: 240 },
    zIndex: 0,
    opacity: 1,
    visible: true,
    locked: true,
    runtimeExport: true
  });
  document.layers.navigation = paintCells(document.layers.navigation, [{ x: 1, y: 1 }], "walkable");
  document.layers.navigation.regions.push({
    id: "WalkableRegion",
    name: "Walkable Region",
    type: "walkable",
    shape: polygonAround({ x: 120, y: 120 }, 90),
    debugColor: "#22c55e",
    enabled: true
  });
  document.layers.collision.push({
    id: "Wall",
    name: "Wall",
    kind: "world",
    shape: polygonAround({ x: 80, y: 80 }),
    collisionLayer: 2,
    collisionMask: 0,
    debugColor: "#ef4444",
    enabled: true
  });
  document.layers.occlusion.push({
    id: "Roof",
    name: "Roof",
    shape: polygonAround({ x: 80, y: 40 }),
    baselineY: 90,
    sortMode: "foot_y",
    zIndex: 120,
    debugColor: "#8b5cf6",
    enabled: true
  });
  document.layers.interactions.push({
    id: "DoorHit",
    name: "Door Hit",
    type: "door",
    targetId: "DoorA",
    primaryAction: "enter",
    shape: { type: "circle", x: 120, y: 120, radius: 24 },
    tags: ["door"],
    enabled: true
  });
  document.layers.doors.push({
    id: "DoorA",
    name: "Door A",
    fromSceneId: "town_runtime",
    toSceneId: "cafe",
    fromPoint: { x: 120, y: 130, facing: "up" },
    toPoint: { x: 20, y: 40, facing: "down" },
    transitionTicks: 2,
    tags: ["door"]
  });
  document.layers.points.push({
    id: "SpawnA",
    name: "Spawn A",
    type: "spawn_point",
    position: { x: 32, y: 32 },
    facing: "down",
    tags: ["player"]
  });
  document.layers.lighting.push({
    id: "Lamp",
    name: "Lamp",
    type: "point",
    position: { x: 150, y: 90 },
    color: "#ffd37a",
    energy: 1.2,
    radius: 180,
    zIndex: 20,
    timeRules: ["night"],
    weatherRules: [],
    enabled: true
  });
  document.layers.lightOccluders.push({
    id: "LightBlock",
    name: "Light Block",
    shape: polygonAround({ x: 170, y: 90 }),
    sdfCollision: true,
    tags: [],
    enabled: true
  });
  document.layers.animations.push({
    id: "WaterAnim",
    name: "Water Anim",
    type: "sprite_frames",
    position: { x: 60, y: 160 },
    fps: 8,
    loop: true,
    autoplay: true,
    zIndex: 10,
    trigger: "auto",
    timeRules: [],
    weatherRules: [],
    enabled: true
  });
  document.layers.effects.push({
    id: "Glow",
    name: "Glow",
    preset: "firefly",
    position: { x: 170, y: 150 },
    emissionShape: { type: "circle", x: 170, y: 150, radius: 64 },
    amount: 24,
    lifetime: 1.2,
    color: "#ffffff",
    zIndex: 80,
    enabledRules: [],
    enabled: true
  });
  document.layers.audio.push({
    id: "RiverSound",
    name: "River Sound",
    type: "point",
    stream: "game/assets/audio/river.ogg",
    position: { x: 190, y: 180 },
    radius: 260,
    volumeDb: -8,
    bus: "Master",
    loop: true,
    timeRules: [],
    weatherRules: [],
    fadeIn: 0.3,
    fadeOut: 0.3,
    enabled: true
  });
  document.layers.camera.push({
    id: "CameraFocus",
    name: "Camera Focus",
    type: "hotspot",
    shape: { type: "circle", x: 120, y: 120, radius: 90 },
    targetPoint: { x: 120, y: 120 },
    zoom: 0.75,
    priority: 1,
    tags: ["plaza"],
    enabled: true
  });
  document.layers.semanticRegions.push({
    id: "Plaza",
    name: "Plaza",
    type: "plaza",
    shape: polygonAround({ x: 120, y: 120 }, 70),
    visibility: "public",
    tags: ["public"],
    defaultActionHints: ["idle", "chat"],
    allowedResidentTags: [],
    privacyLevel: "public"
  });
  return document;
}
