export interface Point2 {
  x: number;
  y: number;
}

export interface Size2 {
  width: number;
  height: number;
}

export interface RectShape {
  type: "rect";
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface CircleShape {
  type: "circle";
  x: number;
  y: number;
  radius: number;
}

export interface PolygonShape {
  type: "polygon";
  points: Point2[];
}

export type Shape = RectShape | CircleShape | PolygonShape;

export type RuntimeLayerKind =
  | "images"
  | "navigation"
  | "collision"
  | "occlusion"
  | "interactions"
  | "doors"
  | "points"
  | "lighting"
  | "lightOccluders"
  | "animations"
  | "effects"
  | "audio"
  | "camera"
  | "semanticRegions";

export type NavigationCellType = "unknown" | "walkable" | "blocked" | "soft_blocked" | "water" | "door";
export type NavigationRegionType = Exclude<NavigationCellType, "unknown">;

export interface NavigationCell {
  x: number;
  y: number;
  type: NavigationCellType;
}

export interface NavigationRegionObject {
  id: string;
  name: string;
  type: NavigationRegionType;
  shape: PolygonShape;
  debugColor: string;
  enabled: boolean;
}

export interface NavigationGrid {
  cellSize: number;
  width: number;
  height: number;
  default: NavigationCellType;
  cells: NavigationCell[];
  regions: NavigationRegionObject[];
}

export interface ImageLayer {
  id: string;
  name: string;
  asset: string;
  kind: "base" | "surface" | "object" | "foreground" | "reference";
  position: Point2;
  size: Size2;
  zIndex: number;
  opacity: number;
  visible: boolean;
  locked: boolean;
  runtimeExport: boolean;
  sourceLayerId?: string;
  tileKey?: string;
}

export interface CollisionLayerObject {
  id: string;
  name: string;
  kind: "world" | "water" | "soft" | "debug";
  shape: PolygonShape;
  buildMode?: "solids" | "segments";
  collisionLayer: number;
  collisionMask: number;
  debugColor: string;
  enabled: boolean;
}

export interface OcclusionObject {
  id: string;
  name: string;
  asset?: string;
  shape: PolygonShape;
  baselineY: number;
  sortMode: "foot_y" | "always_front";
  activationMode?: "foot_inside" | "global";
  zIndex: number;
  debugColor: string;
  enabled: boolean;
}

export interface InteractionObject {
  id: string;
  name: string;
  type: "building" | "door" | "prop" | "dialogue" | "event" | "photo" | "debug";
  targetId: string;
  primaryAction: string;
  shape: Shape;
  tags: string[];
  enabled: boolean;
}

export interface DoorObject {
  id: string;
  name: string;
  fromSceneId: string;
  toSceneId: string;
  fromPoint: Point2 & { facing: Facing };
  toPoint: Point2 & { facing: Facing };
  hitAreaId?: string;
  standPoint?: Point2;
  transitionTicks: number;
  tags: string[];
}

export type Facing = "up" | "down" | "left" | "right";

export interface PointObject {
  id: string;
  name: string;
  type:
    | "spawn_point"
    | "wait_point"
    | "conversation_point"
    | "event_anchor"
    | "camera_hotspot"
    | "schedule_point"
    | "stand_point"
    | "photo_point"
    | "sound_anchor"
    | "effect_anchor"
    | "ai_behavior_anchor";
  position: Point2;
  facing: Facing;
  tags: string[];
}

export interface LightingObject {
  id: string;
  name: string;
  type: "point" | "ambient" | "area" | "flicker";
  position: Point2;
  color: string;
  energy: number;
  radius: number;
  texture?: string;
  zIndex: number;
  timeRules: string[];
  weatherRules: string[];
  animation?: string;
  enabled: boolean;
}

export interface LightOccluderObject {
  id: string;
  name: string;
  shape: PolygonShape;
  sdfCollision: boolean;
  tags: string[];
  enabled: boolean;
}

export interface AnimationObject {
  id: string;
  name: string;
  type: "sprite_frames" | "animation_player" | "shader";
  asset?: string;
  position: Point2;
  fps: number;
  loop: boolean;
  autoplay: boolean;
  zIndex: number;
  trigger: "auto" | "time" | "interaction" | "weather";
  timeRules: string[];
  weatherRules: string[];
  enabled: boolean;
}

export interface EffectObject {
  id: string;
  name: string;
  preset: "rain" | "snow" | "leaves" | "smoke" | "fog" | "spark" | "firefly" | "custom";
  position: Point2;
  emissionShape: Shape;
  amount: number;
  lifetime: number;
  color: string;
  zIndex: number;
  enabledRules: string[];
  enabled: boolean;
}

export interface AudioObject {
  id: string;
  name: string;
  type: "bgm" | "ambient_area" | "point";
  stream?: string;
  position: Point2;
  radius: number;
  volumeDb: number;
  bus: string;
  loop: boolean;
  timeRules: string[];
  weatherRules: string[];
  fadeIn: number;
  fadeOut: number;
  enabled: boolean;
}

export interface CameraObject {
  id: string;
  name: string;
  type: "bounds" | "hotspot" | "event_focus";
  shape: Shape;
  targetPoint: Point2;
  zoom: number;
  priority: number;
  tags: string[];
  enabled: boolean;
}

export interface SemanticRegionObject {
  id: string;
  name: string;
  type: "home" | "cafe" | "library" | "workplace" | "plaza" | "street" | "park" | "water" | "outdoor" | string;
  shape: Shape;
  visibility: "public" | "private" | string;
  tags: string[];
  linkedSceneId?: string;
  defaultActionHints: string[];
  allowedResidentTags: string[];
  privacyLevel: "public" | "semi_private" | "private";
}

export interface MapToolSource {
  kind: "pixelwork_map_stitch" | "godot_scene" | "godot_generated" | "manual";
  root: string;
  packageRoot?: string;
  demoScene?: string;
  godotManifest?: string;
  annotations?: string;
}

export interface MapToolCanvas {
  width: number;
  height: number;
  unit: "pixel";
  defaultGridSize: number;
}

export interface MapToolFileState {
  lastLoadedHash: string;
  lastSavedAt: string;
}

export interface MapToolLayers {
  images: ImageLayer[];
  navigation: NavigationGrid;
  collision: CollisionLayerObject[];
  occlusion: OcclusionObject[];
  interactions: InteractionObject[];
  doors: DoorObject[];
  points: PointObject[];
  lighting: LightingObject[];
  lightOccluders: LightOccluderObject[];
  animations: AnimationObject[];
  effects: EffectObject[];
  audio: AudioObject[];
  camera: CameraObject[];
  semanticRegions: SemanticRegionObject[];
}

export interface MapToolDocument {
  schemaVersion: 1;
  editorVersion: 1;
  mapId: string;
  displayName: string;
  source: MapToolSource;
  canvas: MapToolCanvas;
  fileState: MapToolFileState;
  layers: MapToolLayers;
}

export interface MapToolSelection {
  layer: RuntimeLayerKind;
  id: string;
}

export interface RuntimeMapData {
  schemaVersion: 1;
  mapId: string;
  displayName: string;
  canvas: MapToolCanvas;
  source: MapToolSource;
  layers: Omit<MapToolLayers, "images"> & {
    images: ImageLayer[];
  };
}

export const RUNTIME_LAYER_LABELS: Record<RuntimeLayerKind, string> = {
  images: "图像",
  navigation: "通行",
  collision: "碰撞",
  occlusion: "遮挡",
  interactions: "交互",
  doors: "门",
  points: "点位",
  lighting: "灯光",
  lightOccluders: "挡光",
  animations: "动画",
  effects: "特效",
  audio: "声音",
  camera: "镜头",
  semanticRegions: "AI语义"
};

export const NAVIGATION_CELL_TYPES: NavigationCellType[] = [
  "unknown",
  "walkable",
  "blocked",
  "soft_blocked",
  "water",
  "door"
];
