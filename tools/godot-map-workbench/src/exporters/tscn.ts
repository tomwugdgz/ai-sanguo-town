import earcut, { deviation, flatten } from "earcut";
import polygonClipping, { type Pair, type Polygon } from "polygon-clipping";
import type {
  AnimationObject,
  AudioObject,
  CameraObject,
  EffectObject,
  ImageLayer,
  LightingObject,
  MapToolDocument,
  NavigationRegionType,
  Point2,
  PolygonShape,
  Shape
} from "../model/types";

export function exportLayersTscn(document: MapToolDocument): string {
  const extResources = new ExtResources();
  const subResources = new SubResources();
  const navigationMeshes = buildNavigationMeshes(document);
  const enabledOcclusions = document.layers.occlusion.filter((item) => item.enabled);
  const occlusionTexture = document.layers.images.find((item) => item.kind === "base" && item.visible)
    ?? document.layers.images.find((item) => item.visible);
  const occlusionScriptId = enabledOcclusions.length > 0
    ? extResources.get("game/world/runtime/MapRuntimeOcclusionLayer.gd", "Script")
    : undefined;
  const lines: string[] = [
    '[gd_scene load_steps=1 format=3]',
    "",
    '[node name="MapRuntimeLayers" type="Node2D"]',
    `metadata/map_id = "${escapeString(document.mapId)}"`,
    "",
    '[node name="VisualLayers" type="Node2D" parent="."]'
  ];

  for (const image of document.layers.images.filter((item) => item.runtimeExport)) {
    appendImage(lines, extResources, image);
  }

  lines.push("", '[node name="NavigationDebug" type="Node2D" parent="."]');
  lines.push("visible = false");
  appendNavigationDebug(lines, navigationMeshes);

  lines.push("", '[node name="Collision" type="Node2D" parent="."]');
  lines.push('[node name="WorldBlockCollision" type="StaticBody2D" parent="Collision"]');
  lines.push("collision_layer = 1", "collision_mask = 0");
  lines.push('[node name="WaterBlockCollision" type="StaticBody2D" parent="Collision"]');
  lines.push("collision_layer = 1", "collision_mask = 0");
  for (const collision of document.layers.collision.filter((item) => item.enabled)) {
    const parent = collision.kind === "water" ? "Collision/WaterBlockCollision" : "Collision/WorldBlockCollision";
    appendCollisionPolygon(lines, collision.id, parent, collision.shape, collision.buildMode);
  }

  lines.push("", '[node name="Occlusion" type="Node2D" parent="."]');
  if (occlusionScriptId) {
    lines.push(`script = ExtResource("${occlusionScriptId}")`);
  }
  for (const occlusion of enabledOcclusions) {
    appendRuntimeOcclusion(lines, extResources, occlusion, occlusionTexture);
  }

  lines.push("", '[node name="OcclusionDebug" type="Node2D" parent="."]');
  lines.push("visible = false", "z_index = 220");
  for (const occlusion of enabledOcclusions) {
    appendOcclusionDebug(lines, occlusion);
  }

  lines.push("", '[node name="InteractionAreas" type="Node2D" parent="."]');
  for (const interaction of document.layers.interactions.filter((item) => item.enabled)) {
    appendArea(lines, subResources, interaction.id, "InteractionAreas", interaction.shape);
    lines.push(`metadata/primary_action = "${escapeString(interaction.primaryAction)}"`);
    lines.push(`metadata/target_id = "${escapeString(interaction.targetId)}"`);
  }

  lines.push("", '[node name="Points" type="Node2D" parent="."]');
  for (const point of document.layers.points) {
    appendMarker(lines, point.id, "Points", point.position);
    lines.push(`metadata/point_type = "${escapeString(point.type)}"`);
  }
  for (const door of document.layers.doors) {
    appendMarker(lines, door.id, "Points", door.fromPoint);
    lines.push(`metadata/point_type = "door"`);
    lines.push(`metadata/to_scene_id = "${escapeString(door.toSceneId)}"`);
  }

  lines.push("", '[node name="Lighting" type="Node2D" parent="."]');
  for (const light of document.layers.lighting.filter((item) => item.enabled)) {
    appendLight(lines, light);
  }

  lines.push("", '[node name="LightOccluders" type="Node2D" parent="."]');
  for (const occluder of document.layers.lightOccluders.filter((item) => item.enabled)) {
    const resourceId = subResources.add("OccluderPolygon2D", [`polygon = ${packedVector2Array(occluder.shape.points)}`]);
    lines.push(`[node name="${safeNodeName(occluder.id)}" type="LightOccluder2D" parent="LightOccluders"]`);
    lines.push(`occluder = SubResource("${resourceId}")`);
  }

  lines.push("", '[node name="Animations" type="Node2D" parent="."]');
  for (const animation of document.layers.animations.filter((item) => item.enabled)) {
    appendAnimation(lines, animation);
  }

  lines.push("", '[node name="Effects" type="Node2D" parent="."]');
  for (const effect of document.layers.effects.filter((item) => item.enabled)) {
    appendEffect(lines, effect);
  }

  lines.push("", '[node name="Audio" type="Node2D" parent="."]');
  for (const audio of document.layers.audio.filter((item) => item.enabled)) {
    appendAudio(lines, extResources, audio);
  }

  lines.push("", '[node name="CameraZones" type="Node2D" parent="."]');
  for (const camera of document.layers.camera.filter((item) => item.enabled)) {
    appendCamera(lines, camera);
  }

  lines.push("", '[node name="DebugOverlay" type="Node2D" parent="."]');
  lines.push("visible = false", "z_index = 220");
  appendDebugOverlay(lines, document, navigationMeshes);

  const header = [`[gd_scene load_steps=${Math.max(1, extResources.count + subResources.count + 1)} format=3]`];
  return [
    ...header,
    ...extResources.lines(),
    ...subResources.lines,
    ...lines.slice(2)
  ].join("\n") + "\n";
}

class ExtResources {
  private resources = new Map<string, string>();

  get(path: string, type: string): string {
    const key = `${type}:${path}`;
    const existing = this.resources.get(key);
    if (existing) return existing;
    const id = `res_${this.resources.size + 1}`;
    this.resources.set(key, id);
    return id;
  }

  get count(): number {
    return this.resources.size;
  }

  lines(): string[] {
    const lines: string[] = [];
    for (const [key, id] of this.resources) {
      const separator = key.indexOf(":");
      const type = key.slice(0, separator);
      const path = key.slice(separator + 1);
      lines.push(`[ext_resource type="${type}" path="${toGodotResourcePath(path)}" id="${id}"]`);
    }
    if (lines.length > 0) lines.push("");
    return lines;
  }
}

class SubResources {
  lines: string[] = [];
  count = 0;

  add(type: string, properties: string[]): string {
    this.count += 1;
    const id = `${type}_${this.count}`;
    this.lines.push(`[sub_resource type="${type}" id="${id}"]`);
    this.lines.push(...properties);
    this.lines.push("");
    return id;
  }
}

function appendImage(lines: string[], resources: ExtResources, image: ImageLayer): void {
  const resId = resources.get(image.asset, "Texture2D");
  lines.push(`[node name="${safeNodeName(image.id)}" type="Sprite2D" parent="VisualLayers"]`);
  lines.push(`position = ${vector2(image.position)}`);
  lines.push(`texture = ExtResource("${resId}")`);
  lines.push(`centered = false`);
  lines.push(`z_index = ${Math.round(image.zIndex)}`);
  lines.push(`modulate = Color(1, 1, 1, ${clamp01(image.opacity)})`);
}

function appendNavigationDebug(lines: string[], meshes: NavigationMesh[]): void {
  for (const mesh of meshes) {
    appendNavigationMesh(lines, mesh, "NavigationDebug", `nav_${mesh.type}_merged`, 188);
  }
}

function appendDebugOverlay(lines: string[], document: MapToolDocument, navigationMeshes: NavigationMesh[]): void {
  for (const mesh of navigationMeshes) {
    appendNavigationMesh(lines, mesh, "DebugOverlay", `debug_nav_${mesh.type}_merged`, 204);
  }
  for (const collision of document.layers.collision.filter((item) => item.enabled)) {
    appendDebugShape(lines, `debug_${collision.id}`, "DebugOverlay", collision.shape, collision.kind === "water" ? "#3b82f6" : "#ef4444", 210);
  }
  for (const interaction of document.layers.interactions.filter((item) => item.enabled)) {
    appendDebugShape(lines, `debug_${interaction.id}`, "DebugOverlay", interaction.shape, "#38bdf8", 212);
  }
  for (const occluder of document.layers.lightOccluders.filter((item) => item.enabled)) {
    appendDebugShape(lines, `debug_${occluder.id}`, "DebugOverlay", occluder.shape, "#facc15", 214);
  }
  for (const semantic of document.layers.semanticRegions) {
    appendDebugShape(lines, `debug_${semantic.id}`, "DebugOverlay", semantic.shape, "#22c55e", 205);
  }
}

interface NavigationMesh {
  type: NavigationRegionType;
  vertices: Point2[];
  triangles: number[][];
  componentCount: number;
  sourceCount: number;
}

const NAVIGATION_TYPES: NavigationRegionType[] = ["walkable", "blocked", "soft_blocked", "water", "door"];

function buildNavigationMeshes(document: MapToolDocument): NavigationMesh[] {
  const sourcePolygons = new Map<NavigationRegionType, Polygon[]>();
  const sourceCounts = new Map<NavigationRegionType, number>();
  for (const type of NAVIGATION_TYPES) {
    sourcePolygons.set(type, []);
    sourceCounts.set(type, 0);
  }

  for (const region of document.layers.navigation.regions ?? []) {
    if (!region.enabled) continue;
    appendNavigationSource(sourcePolygons, sourceCounts, region.type, region.shape.points);
  }

  const grid = document.layers.navigation;
  for (const cell of grid.cells) {
    if (cell.type === "unknown") continue;
    const x = cell.x * grid.cellSize;
    const y = cell.y * grid.cellSize;
    appendNavigationSource(sourcePolygons, sourceCounts, cell.type, [
      { x, y },
      { x: x + grid.cellSize, y },
      { x: x + grid.cellSize, y: y + grid.cellSize },
      { x, y: y + grid.cellSize }
    ]);
  }

  const meshes: NavigationMesh[] = [];
  for (const type of NAVIGATION_TYPES) {
    const polygons = sourcePolygons.get(type) ?? [];
    if (polygons.length === 0) continue;
    const merged = polygonClipping.union(polygons[0], ...polygons.slice(1));
    const vertices: Point2[] = [];
    const triangles: number[][] = [];

    for (const mergedPolygon of merged) {
      const rings = mergedPolygon
        .map((ring) => cleanRing(ring))
        .filter((ring) => ring.length >= 3);
      if (rings.length === 0) continue;
      const flattened = flatten(rings);
      const triangleIndices = earcut(flattened.vertices, flattened.holes, flattened.dimensions);
      const triangulationDeviation = deviation(
        flattened.vertices,
        flattened.holes,
        flattened.dimensions,
        triangleIndices
      );
      if (triangleIndices.length === 0 || triangulationDeviation > 0.000001) {
        throw new Error(`通行区域 ${type} 自动修复失败：无法生成可靠三角网格。`);
      }

      const vertexOffset = vertices.length;
      for (let index = 0; index < flattened.vertices.length; index += flattened.dimensions) {
        vertices.push({ x: flattened.vertices[index], y: flattened.vertices[index + 1] });
      }
      for (let index = 0; index < triangleIndices.length; index += 3) {
        triangles.push([
          vertexOffset + triangleIndices[index],
          vertexOffset + triangleIndices[index + 1],
          vertexOffset + triangleIndices[index + 2]
        ]);
      }
    }

    if (vertices.length > 0 && triangles.length > 0) {
      meshes.push({
        type,
        vertices,
        triangles,
        componentCount: merged.length,
        sourceCount: sourceCounts.get(type) ?? 0
      });
    }
  }
  return meshes;
}

function appendNavigationSource(
  polygons: Map<NavigationRegionType, Polygon[]>,
  counts: Map<NavigationRegionType, number>,
  type: NavigationRegionType,
  points: Point2[]
): void {
  const ring = cleanRing(points.map((point) => [point.x, point.y] as Pair));
  if (ring.length < 3) return;
  polygons.get(type)?.push([ring]);
  counts.set(type, (counts.get(type) ?? 0) + 1);
}

function cleanRing(ring: ReadonlyArray<Readonly<Pair>>): Pair[] {
  const cleaned: Pair[] = [];
  for (const point of ring) {
    const next: Pair = [numberForGeometry(point[0]), numberForGeometry(point[1])];
    const previous = cleaned[cleaned.length - 1];
    if (!previous || previous[0] !== next[0] || previous[1] !== next[1]) {
      cleaned.push(next);
    }
  }
  if (cleaned.length > 1) {
    const first = cleaned[0];
    const last = cleaned[cleaned.length - 1];
    if (first[0] === last[0] && first[1] === last[1]) {
      cleaned.pop();
    }
  }
  return cleaned;
}

function appendNavigationMesh(
  lines: string[],
  mesh: NavigationMesh,
  parent: string,
  id: string,
  zIndex: number
): void {
  lines.push(`[node name="${safeNodeName(id)}" type="Polygon2D" parent="${parent}"]`);
  lines.push(`polygon = ${packedVector2Array(mesh.vertices)}`);
  lines.push(`polygons = ${packedInt32ArrayList(mesh.triangles)}`);
  lines.push(`color = ${colorValue(navigationColor(mesh.type), 0.35)}`);
  lines.push(`z_index = ${Math.round(zIndex)}`);
  lines.push(`metadata/navigation_type = "${escapeString(mesh.type)}"`);
  lines.push(`metadata/source_count = ${mesh.sourceCount}`);
  lines.push(`metadata/component_count = ${mesh.componentCount}`);
  lines.push(`metadata/triangle_count = ${mesh.triangles.length}`);
  lines.push("metadata/auto_repaired = true");
}

function appendDebugShape(lines: string[], id: string, parent: string, shape: Shape, color: string, zIndex: number): void {
  if (shape.type === "circle") {
    const points = circlePoints(shape.x, shape.y, shape.radius, 24);
    appendPolygon2D(lines, id, parent, { type: "polygon", points }, color, zIndex);
    return;
  }
  if (shape.type === "rect") {
    appendPolygon2D(lines, id, parent, { type: "polygon", points: rectPoints(shape.x, shape.y, shape.width, shape.height) }, color, zIndex);
    return;
  }
  appendPolygon2D(lines, id, parent, shape, color, zIndex);
}

function appendCollisionPolygon(
  lines: string[],
  id: string,
  parent: string,
  shape: PolygonShape,
  buildMode: "solids" | "segments" | undefined
): void {
  lines.push(`[node name="${safeNodeName(id)}" type="CollisionPolygon2D" parent="${parent}"]`);
  if (buildMode === "segments") {
    lines.push("build_mode = 1");
  }
  lines.push(`polygon = ${packedVector2Array(shape.points)}`);
}

function appendRuntimeOcclusion(
  lines: string[],
  resources: ExtResources,
  occlusion: MapToolDocument["layers"]["occlusion"][number],
  textureImage: ImageLayer | undefined
): void {
  lines.push(`[node name="${safeNodeName(occlusion.id)}" type="Polygon2D" parent="Occlusion"]`);
  lines.push(`polygon = ${packedVector2Array(occlusion.shape.points)}`);
  if (textureImage) {
    const textureId = resources.get(textureImage.asset, "Texture2D");
    const uvPoints = occlusion.shape.points.map((point) => ({
      x: point.x - textureImage.position.x,
      y: point.y - textureImage.position.y
    }));
    lines.push(`uv = ${packedVector2Array(uvPoints)}`);
    lines.push(`texture = ExtResource("${textureId}")`);
    lines.push("texture_filter = 1");
    lines.push("color = Color(1, 1, 1, 1)");
  } else {
    lines.push(`color = ${colorValue(occlusion.debugColor, 0.35)}`);
  }
  lines.push(`z_index = ${Math.round(occlusion.zIndex)}`);
  lines.push(`metadata/base_z_index = ${Math.round(occlusion.zIndex)}`);
  lines.push(`metadata/baseline_y = ${number(occlusion.baselineY)}`);
  lines.push(`metadata/sort_mode = "${escapeString(occlusion.sortMode)}"`);
  lines.push(`metadata/activation_mode = "${escapeString(occlusion.activationMode ?? "foot_inside")}"`);
}

function appendOcclusionDebug(
  lines: string[],
  occlusion: MapToolDocument["layers"]["occlusion"][number]
): void {
  const id = safeNodeName(occlusion.id);
  const color = occlusion.debugColor || "#8b5cf6";
  appendDebugShape(lines, `debug_${id}`, "OcclusionDebug", occlusion.shape, color, 0);
  if (occlusion.sortMode !== "foot_y") return;
  const xValues = occlusion.shape.points.map((point) => point.x);
  if (xValues.length === 0) return;
  lines.push(`[node name="debug_${id}_baseline" type="Line2D" parent="OcclusionDebug"]`);
  lines.push(`points = ${packedVector2Array([
    { x: Math.min(...xValues), y: occlusion.baselineY },
    { x: Math.max(...xValues), y: occlusion.baselineY }
  ])}`);
  lines.push("width = 2.0");
  lines.push(`default_color = ${colorValue(color, 0.95)}`);
  lines.push("z_index = 1");
}

function appendPolygon2D(lines: string[], id: string, parent: string, shape: PolygonShape, color: string, zIndex: number): void {
  lines.push(`[node name="${safeNodeName(id)}" type="Polygon2D" parent="${parent}"]`);
  lines.push(`polygon = ${packedVector2Array(shape.points)}`);
  lines.push(`color = ${colorValue(color, 0.35)}`);
  lines.push(`z_index = ${Math.round(zIndex)}`);
}

function appendArea(lines: string[], resources: SubResources, id: string, parent: string, shape: Shape): void {
  lines.push(`[node name="${safeNodeName(id)}" type="Area2D" parent="${parent}"]`);
  lines.push("collision_layer = 8", "collision_mask = 1");
  if (shape.type === "circle") {
    const resourceId = resources.add("CircleShape2D", [`radius = ${number(shape.radius)}`]);
    lines.push(`[node name="Shape" type="CollisionShape2D" parent="${parent}/${safeNodeName(id)}"]`);
    lines.push(`position = ${vector2({ x: shape.x, y: shape.y })}`);
    lines.push(`shape = SubResource("${resourceId}")`);
  } else {
    const points = shape.type === "rect" ? rectPoints(shape.x, shape.y, shape.width, shape.height) : shape.points;
    lines.push(`[node name="Shape" type="CollisionPolygon2D" parent="${parent}/${safeNodeName(id)}"]`);
    lines.push(`polygon = ${packedVector2Array(points)}`);
  }
}

function appendMarker(lines: string[], id: string, parent: string, point: Point2): void {
  lines.push(`[node name="${safeNodeName(id)}" type="Marker2D" parent="${parent}"]`);
  lines.push(`position = ${vector2(point)}`);
}

function appendLight(lines: string[], light: LightingObject): void {
  lines.push(`[node name="${safeNodeName(light.id)}" type="PointLight2D" parent="Lighting"]`);
  lines.push(`position = ${vector2(light.position)}`);
  lines.push(`color = ${colorValue(light.color, 1)}`);
  lines.push(`energy = ${number(light.energy)}`);
  lines.push(`texture_scale = ${number(Math.max(0.1, light.radius / 256))}`);
  lines.push(`z_index = ${Math.round(light.zIndex)}`);
}

function appendAnimation(lines: string[], animation: AnimationObject): void {
  lines.push(`[node name="${safeNodeName(animation.id)}" type="AnimatedSprite2D" parent="Animations"]`);
  lines.push(`position = ${vector2(animation.position)}`);
  lines.push(`z_index = ${Math.round(animation.zIndex)}`);
  lines.push(`autoplay = "${animation.autoplay ? "default" : ""}"`);
  lines.push(`metadata/fps = ${number(animation.fps)}`);
}

function appendEffect(lines: string[], effect: EffectObject): void {
  lines.push(`[node name="${safeNodeName(effect.id)}" type="GPUParticles2D" parent="Effects"]`);
  lines.push(`position = ${vector2(effect.position)}`);
  lines.push(`amount = ${Math.round(effect.amount)}`);
  lines.push(`lifetime = ${number(effect.lifetime)}`);
  lines.push(`z_index = ${Math.round(effect.zIndex)}`);
  lines.push(`metadata/preset = "${escapeString(effect.preset)}"`);
}

function appendAudio(lines: string[], resources: ExtResources, audio: AudioObject): void {
  lines.push(`[node name="${safeNodeName(audio.id)}" type="${audio.type === "bgm" ? "AudioStreamPlayer" : "AudioStreamPlayer2D"}" parent="Audio"]`);
  if (audio.type !== "bgm") {
    lines.push(`position = ${vector2(audio.position)}`);
    lines.push(`max_distance = ${number(audio.radius)}`);
  }
  if (audio.stream) {
    const resId = resources.get(audio.stream, "AudioStream");
    lines.push(`stream = ExtResource("${resId}")`);
  }
  lines.push(`volume_db = ${number(audio.volumeDb)}`);
  lines.push(`bus = "${escapeString(audio.bus)}"`);
  lines.push(`autoplay = false`);
}

function appendCamera(lines: string[], camera: CameraObject): void {
  appendMarker(lines, camera.id, "CameraZones", camera.targetPoint);
  lines.push(`metadata/camera_type = "${escapeString(camera.type)}"`);
  lines.push(`metadata/zoom = ${number(camera.zoom)}`);
  lines.push(`metadata/priority = ${Math.round(camera.priority)}`);
}

function rectPoints(x: number, y: number, width: number, height: number): Point2[] {
  return [
    { x, y },
    { x: x + width, y },
    { x: x + width, y: y + height },
    { x, y: y + height }
  ];
}

function circlePoints(x: number, y: number, radius: number, segments: number): Point2[] {
  const points: Point2[] = [];
  const safeSegments = Math.max(8, segments);
  for (let index = 0; index < safeSegments; index += 1) {
    const angle = (Math.PI * 2 * index) / safeSegments;
    points.push({
      x: x + Math.cos(angle) * radius,
      y: y + Math.sin(angle) * radius
    });
  }
  return points;
}

function packedVector2Array(points: Point2[]): string {
  return `PackedVector2Array(${points.flatMap((point) => [number(point.x), number(point.y)]).join(", ")})`;
}

function packedInt32ArrayList(polygons: number[][]): string {
  return `[${polygons.map((polygon) => `PackedInt32Array(${polygon.join(", ")})`).join(", ")}]`;
}

function vector2(point: Point2): string {
  return `Vector2(${number(point.x)}, ${number(point.y)})`;
}

function number(value: number): string {
  return Number.isFinite(value) ? String(Math.round(value * 1000) / 1000) : "0";
}

function numberForGeometry(value: number): number {
  return Number.isFinite(value) ? Math.round(value * 1000) / 1000 : 0;
}

function colorValue(hex: string, fallbackAlpha: number): string {
  const normalized = hex.replace("#", "");
  if (!/^[0-9a-fA-F]{6}$/.test(normalized)) {
    return `Color(1, 1, 1, ${fallbackAlpha})`;
  }
  const r = parseInt(normalized.slice(0, 2), 16) / 255;
  const g = parseInt(normalized.slice(2, 4), 16) / 255;
  const b = parseInt(normalized.slice(4, 6), 16) / 255;
  return `Color(${number(r)}, ${number(g)}, ${number(b)}, ${fallbackAlpha})`;
}

function navigationColor(type: string): string {
  if (type === "walkable") return "#22c55e";
  if (type === "blocked") return "#ef4444";
  if (type === "soft_blocked") return "#f59e0b";
  if (type === "water") return "#38bdf8";
  if (type === "door") return "#a855f7";
  return "#ffffff";
}

function safeNodeName(value: string): string {
  return (value || "node").replace(/[^A-Za-z0-9_]/g, "_");
}

function toGodotResourcePath(value: string): string {
  const normalized = value.replace(/\\/g, "/");
  const marker = "/game/";
  const markerIndex = normalized.indexOf(marker);
  if (markerIndex >= 0) {
    return `res://${normalized.slice(markerIndex + marker.length)}`;
  }
  if (normalized.startsWith("game/")) {
    return `res://${normalized.slice("game/".length)}`;
  }
  if (normalized.startsWith("res://")) {
    return normalized;
  }
  return `res://${normalized}`;
}

function clamp01(value: number): number {
  return Math.max(0, Math.min(1, value));
}

function escapeString(value: string): string {
  return value.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
}
