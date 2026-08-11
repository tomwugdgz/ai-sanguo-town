import {
  type AnimationObject,
  type AudioObject,
  type CameraObject,
  type CollisionLayerObject,
  type DoorObject,
  type EffectObject,
  type InteractionObject,
  type LightOccluderObject,
  type LightingObject,
  type MapToolDocument,
  type NavigationCell,
  type NavigationCellType,
  type NavigationGrid,
  type NavigationRegionObject,
  type OcclusionObject,
  type Point2,
  type PointObject,
  type PolygonShape,
  type RuntimeLayerKind,
  type SemanticRegionObject
} from "./types";

export const DEFAULT_CELL_SIZE = 24;

export function createEmptyMapDocument(mapId: string, displayName = mapId, width = 1024, height = 1024): MapToolDocument {
  return {
    schemaVersion: 1,
    editorVersion: 1,
    mapId,
    displayName,
    source: {
      kind: "manual",
      root: ""
    },
    canvas: {
      width,
      height,
      unit: "pixel",
      defaultGridSize: DEFAULT_CELL_SIZE
    },
    fileState: {
      lastLoadedHash: "",
      lastSavedAt: ""
    },
    layers: {
      images: [],
      navigation: createNavigationGrid(width, height, DEFAULT_CELL_SIZE),
      collision: [],
      occlusion: [],
      interactions: [],
      doors: [],
      points: [],
      lighting: [],
      lightOccluders: [],
      animations: [],
      effects: [],
      audio: [],
      camera: [],
      semanticRegions: []
    }
  };
}

export function createNavigationGrid(width: number, height: number, cellSize: number): NavigationGrid {
  const safeCellSize = Math.max(1, Math.round(cellSize));
  return {
    cellSize: safeCellSize,
    width: Math.max(1, Math.ceil(width / safeCellSize)),
    height: Math.max(1, Math.ceil(height / safeCellSize)),
    default: "unknown",
    cells: [],
    regions: []
  };
}

export function stableMapToolDocument(document: MapToolDocument): MapToolDocument {
  return {
    ...clone(document),
    schemaVersion: 1,
    editorVersion: 1,
    layers: {
      images: [...document.layers.images].sort(compareById),
      navigation: stableNavigationGrid(document.layers.navigation),
      collision: [...document.layers.collision].sort(compareById),
      occlusion: document.layers.occlusion
        .map((occlusion) => ({
          ...occlusion,
          activationMode: occlusion.activationMode ?? "foot_inside"
        }))
        .sort(compareById),
      interactions: [...document.layers.interactions].sort(compareById),
      doors: [...document.layers.doors].sort(compareById),
      points: [...document.layers.points].sort(compareById),
      lighting: [...document.layers.lighting].sort(compareById),
      lightOccluders: [...document.layers.lightOccluders].sort(compareById),
      animations: [...document.layers.animations].sort(compareById),
      effects: [...document.layers.effects].sort(compareById),
      audio: [...document.layers.audio].sort(compareById),
      camera: [...document.layers.camera].sort(compareById),
      semanticRegions: [...document.layers.semanticRegions].sort(compareById)
    }
  };
}

export function stableNavigationGrid(grid: NavigationGrid): NavigationGrid {
  return {
    ...grid,
    cells: [...grid.cells].sort(compareCells),
    regions: [...(grid.regions ?? [])].sort(compareById)
  };
}

export function getCellType(grid: NavigationGrid, x: number, y: number): NavigationCellType {
  if (x < 0 || y < 0 || x >= grid.width || y >= grid.height) {
    return grid.default;
  }
  return grid.cells.find((cell) => cell.x === x && cell.y === y)?.type ?? grid.default;
}

export function paintCells(grid: NavigationGrid, cells: Array<{ x: number; y: number }>, type: NavigationCellType): NavigationGrid {
  const byKey = new Map<string, NavigationCell>();
  for (const cell of grid.cells) {
    byKey.set(cellKey(cell.x, cell.y), { ...cell });
  }
  for (const cell of cells) {
    if (cell.x < 0 || cell.y < 0 || cell.x >= grid.width || cell.y >= grid.height) {
      continue;
    }
    if (type === grid.default) {
      byKey.delete(cellKey(cell.x, cell.y));
    } else {
      byKey.set(cellKey(cell.x, cell.y), { x: cell.x, y: cell.y, type });
    }
  }
  return { ...grid, cells: [...byKey.values()].sort(compareCells), regions: grid.regions ?? [] };
}

export function cellsForBrush(centerX: number, centerY: number, size: number, grid: NavigationGrid): Array<{ x: number; y: number }> {
  const safeSize = Math.max(1, Math.round(size));
  const half = Math.floor(safeSize / 2);
  const cells: Array<{ x: number; y: number }> = [];
  for (let dy = 0; dy < safeSize; dy += 1) {
    for (let dx = 0; dx < safeSize; dx += 1) {
      const x = centerX - half + dx;
      const y = centerY - half + dy;
      if (x >= 0 && y >= 0 && x < grid.width && y < grid.height) {
        cells.push({ x, y });
      }
    }
  }
  return cells;
}

export function pointToCell(point: Point2, grid: NavigationGrid): { x: number; y: number } {
  return {
    x: Math.floor(point.x / grid.cellSize),
    y: Math.floor(point.y / grid.cellSize)
  };
}

export function polygonAround(point: Point2, radius = 32): PolygonShape {
  return {
    type: "polygon",
    points: [
      { x: Math.round(point.x - radius), y: Math.round(point.y - radius) },
      { x: Math.round(point.x + radius), y: Math.round(point.y - radius) },
      { x: Math.round(point.x + radius), y: Math.round(point.y + radius) },
      { x: Math.round(point.x - radius), y: Math.round(point.y + radius) }
    ]
  };
}

export function makeDefaultPolygonObject(layer: RuntimeLayerKind, id: string, point: Point2) {
  const shape = polygonAround(point, 40);
  if (layer === "navigation") {
    return {
      id,
      name: "新通行区",
      type: "walkable",
      shape,
      debugColor: navigationRegionColor("walkable"),
      enabled: true
    } satisfies NavigationRegionObject;
  }
  if (layer === "collision") {
    return {
      id,
      name: "新碰撞",
      kind: "world",
      shape,
      collisionLayer: 1,
      collisionMask: 0,
      debugColor: "#ef4444",
      enabled: true
    } satisfies CollisionLayerObject;
  }
  if (layer === "occlusion") {
    return {
      id,
      name: "新遮挡",
      shape,
      baselineY: Math.round(point.y + 40),
      sortMode: "foot_y",
      activationMode: "foot_inside",
      zIndex: 100,
      debugColor: "#8b5cf6",
      enabled: true
    } satisfies OcclusionObject;
  }
  if (layer === "interactions") {
    return {
      id,
      name: "新交互区",
      type: "debug",
      targetId: "",
      primaryAction: "inspect",
      shape,
      tags: [],
      enabled: true
    } satisfies InteractionObject;
  }
  if (layer === "lightOccluders") {
    return {
      id,
      name: "新挡光",
      shape,
      sdfCollision: true,
      tags: [],
      enabled: true
    } satisfies LightOccluderObject;
  }
  return {
    id,
    name: "新语义区",
    type: "outdoor",
    shape,
    visibility: "public",
    tags: ["public"],
    defaultActionHints: [],
    allowedResidentTags: [],
    privacyLevel: "public"
  } satisfies SemanticRegionObject;
}

export function makeDefaultPointObject(layer: RuntimeLayerKind, id: string, point: Point2) {
  const position = { x: Math.round(point.x), y: Math.round(point.y) };
  if (layer === "doors") {
    return {
      id,
      name: "新门点",
      fromSceneId: "",
      toSceneId: "",
      fromPoint: { ...position, facing: "up" },
      toPoint: { x: 0, y: 0, facing: "down" },
      standPoint: position,
      transitionTicks: 2,
      tags: ["door"]
    } satisfies DoorObject;
  }
  if (layer === "lighting") {
    return {
      id,
      name: "新灯光",
      type: "point",
      position,
      color: "#ffd37a",
      energy: 1,
      radius: 180,
      zIndex: 20,
      timeRules: [],
      weatherRules: [],
      enabled: true
    } satisfies LightingObject;
  }
  if (layer === "animations") {
    return {
      id,
      name: "新动画",
      type: "sprite_frames",
      position,
      fps: 8,
      loop: true,
      autoplay: true,
      zIndex: 10,
      trigger: "auto",
      timeRules: [],
      weatherRules: [],
      enabled: true
    } satisfies AnimationObject;
  }
  if (layer === "effects") {
    return {
      id,
      name: "新特效",
      preset: "custom",
      position,
      emissionShape: { type: "circle", ...position, radius: 96 },
      amount: 32,
      lifetime: 1.5,
      color: "#ffffff",
      zIndex: 80,
      enabledRules: [],
      enabled: true
    } satisfies EffectObject;
  }
  if (layer === "audio") {
    return {
      id,
      name: "新声音",
      type: "point",
      position,
      radius: 240,
      volumeDb: -6,
      bus: "Master",
      loop: true,
      timeRules: [],
      weatherRules: [],
      fadeIn: 0.3,
      fadeOut: 0.3,
      enabled: true
    } satisfies AudioObject;
  }
  if (layer === "camera") {
    return {
      id,
      name: "新镜头点",
      type: "hotspot",
      shape: { type: "circle", ...position, radius: 160 },
      targetPoint: position,
      zoom: 1,
      priority: 0,
      tags: [],
      enabled: true
    } satisfies CameraObject;
  }
  return {
    id,
    name: "新点位",
    type: "stand_point",
    position,
    facing: "down",
    tags: []
  } satisfies PointObject;
}

export function nextId(document: MapToolDocument, layer: RuntimeLayerKind, prefix: string): string {
  const ids = new Set(idsForLayer(document, layer));
  let index = 1;
  let id = `${prefix}_${index.toString().padStart(3, "0")}`;
  while (ids.has(id)) {
    index += 1;
    id = `${prefix}_${index.toString().padStart(3, "0")}`;
  }
  return id;
}

export function idsForLayer(document: MapToolDocument, layer: RuntimeLayerKind): string[] {
  if (layer === "navigation") return (document.layers.navigation.regions ?? []).map((item) => item.id);
  return (document.layers[layer] as Array<{ id: string }>).map((item) => item.id);
}

export function clone<T>(value: T): T {
  return structuredClone(value);
}

export function compareById<T extends { id: string }>(a: T, b: T): number {
  return a.id.localeCompare(b.id);
}

function compareCells(a: NavigationCell, b: NavigationCell): number {
  if (a.y !== b.y) return a.y - b.y;
  if (a.x !== b.x) return a.x - b.x;
  return a.type.localeCompare(b.type);
}

function cellKey(x: number, y: number): string {
  return `${x},${y}`;
}

function navigationRegionColor(type: NavigationCellType): string {
  if (type === "walkable") return "#22c55e";
  if (type === "blocked") return "#ef4444";
  if (type === "soft_blocked") return "#f59e0b";
  if (type === "water") return "#38bdf8";
  if (type === "door") return "#a855f7";
  return "#94a3b8";
}
