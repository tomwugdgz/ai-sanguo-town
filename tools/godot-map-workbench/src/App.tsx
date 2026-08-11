import { useEffect, useMemo, useRef, useState, type PointerEvent as ReactPointerEvent, type WheelEvent } from "react";
import {
  ArrowDown,
  ArrowLeft,
  ArrowRight,
  ArrowUp,
  Brush,
  CheckCircle2,
  Copy,
  Download,
  Eraser,
  Eye,
  EyeOff,
  FileDown,
  FolderOpen,
  Layers,
  LocateFixed,
  Lock,
  Map,
  Maximize2,
  MousePointer2,
  PenLine,
  Plus,
  RefreshCw,
  Save,
  Search,
  Trash2,
  Redo2,
  Undo2,
  Unlock,
  XCircle,
  ZoomIn,
  ZoomOut
} from "lucide-react";
import {
  importPixelworkPackage,
  listPixelworkPackages,
  loadMapToolDocument,
  pickMapSourceFolder,
  saveMapToolDocument,
  type PixelworkPackageSummary
} from "./shared/api";
import { localFileUrl } from "./shared/endpoints";
import {
  cellsForBrush,
  clone,
  makeDefaultPointObject,
  makeDefaultPolygonObject,
  nextId,
  paintCells,
  pointToCell,
  stableMapToolDocument
} from "./model/mapDocument";
import type {
  DoorObject,
  ImageLayer,
  MapToolDocument,
  MapToolSelection,
  NavigationCellType,
  NavigationRegionObject,
  NavigationRegionType,
  Point2,
  PolygonShape,
  RuntimeLayerKind,
  Shape
} from "./model/types";
import { NAVIGATION_CELL_TYPES, RUNTIME_LAYER_LABELS } from "./model/types";
import { validateMapToolDocument, type ValidationIssue } from "./validators/validate";

type ToolMode = "select" | "brush" | "polygon" | "point" | "erase";
type WorkbenchModeValue =
  | "select"
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
type PointLayer = "points" | "doors" | "lighting" | "animations" | "effects" | "audio" | "camera";
type PolygonLayer = "navigation" | "collision" | "occlusion" | "interactions" | "lightOccluders" | "semanticRegions";
type ImageKind = ImageLayer["kind"];
type SourceKind = PixelworkPackageSummary["sourceKind"];

const POLYGON_LAYERS: PolygonLayer[] = ["navigation", "collision", "occlusion", "interactions", "lightOccluders", "semanticRegions"];
const POINT_LAYERS: PointLayer[] = ["points", "doors", "lighting", "animations", "effects", "audio", "camera"];
const ALL_LAYERS = Object.keys(RUNTIME_LAYER_LABELS) as RuntimeLayerKind[];
const ADVANCED_LAYERS: RuntimeLayerKind[] = ["lighting", "lightOccluders", "animations", "effects", "audio", "camera"];
const DEFAULT_MAP_ID = "town_art_pipeline_demo";
const MAX_HISTORY = 80;
const NUDGE_PIXELS = 24;
const IMAGE_KINDS: ImageKind[] = ["base", "surface", "object", "foreground", "reference"];
const QUICK_WORKBENCH_MODES: WorkbenchModeValue[] = ["select", "navigation", "collision", "occlusion", "interactions", "doors", "points", "semanticRegions"];
const LAYER_GROUPS: Array<{ title: string; layers: RuntimeLayerKind[] }> = [
  { title: "图像与通行", layers: ["images", "navigation"] },
  { title: "区域与阻挡", layers: ["collision", "occlusion", "interactions", "semanticRegions"] },
  { title: "点位", layers: ["doors", "points"] }
];
const WORKBENCH_MODES: Array<{ value: WorkbenchModeValue; label: string; tool: ToolMode; layer: RuntimeLayerKind }> = [
  { value: "select", label: "选择/改点", tool: "select", layer: "collision" },
  { value: "navigation", label: "通行多边形", tool: "polygon", layer: "navigation" },
  { value: "collision", label: "碰撞多边形", tool: "polygon", layer: "collision" },
  { value: "occlusion", label: "遮挡多边形", tool: "polygon", layer: "occlusion" },
  { value: "interactions", label: "交互多边形", tool: "polygon", layer: "interactions" },
  { value: "doors", label: "门点", tool: "point", layer: "doors" },
  { value: "points", label: "点位", tool: "point", layer: "points" },
  { value: "lighting", label: "灯光点", tool: "point", layer: "lighting" },
  { value: "lightOccluders", label: "挡光多边形", tool: "polygon", layer: "lightOccluders" },
  { value: "animations", label: "动画点", tool: "point", layer: "animations" },
  { value: "effects", label: "特效点", tool: "point", layer: "effects" },
  { value: "audio", label: "声音点", tool: "point", layer: "audio" },
  { value: "camera", label: "镜头点", tool: "point", layer: "camera" },
  { value: "semanticRegions", label: "AI语义区", tool: "polygon", layer: "semanticRegions" }
];
const PRIMARY_WORKBENCH_MODES = WORKBENCH_MODES.filter((mode) => !ADVANCED_LAYERS.includes(mode.layer));

const LAYER_RUNTIME_HINTS: Record<RuntimeLayerKind, { title: string; body: string }> = {
  images: {
    title: "图像层",
    body: "用于对齐地图美术；运行时可生成 Sprite2D，通常不在这里手改。"
  },
  navigation: {
    title: "通行多边形",
    body: "圈出可走、阻挡、水域、软阻挡和门口区域；格子刷只作为旧数据兼容和小范围修补。"
  },
  collision: {
    title: "碰撞多边形",
    body: "生成 StaticBody2D/CollisionPolygon2D，保存后 Godot 运行窗口会热重载并立即参与阻挡。"
  },
  occlusion: {
    title: "前景遮挡",
    body: "标屋檐、树冠、摊棚等会盖住角色的区域，baselineY 用来做脚底排序。"
  },
  interactions: {
    title: "交互区",
    body: "生成 Area2D；玩家或居民进入后可触发提示、调查、对话、事件或切场景逻辑。"
  },
  doors: {
    title: "门",
    body: "记录跨场景入口、落点和朝向，是室内外切换和 AI 跨场景移动的关键数据。"
  },
  points: {
    title: "点位",
    body: "放出生点、等待点、对话点、巡逻点、行为锚点，给居民调度和剧情事件引用。"
  },
  lighting: {
    title: "灯光",
    body: "放路灯、窗光、火光等点光源，后续可绑定昼夜和天气规则。"
  },
  lightOccluders: {
    title: "挡光",
    body: "标墙体、建筑和大物件的光照遮挡边界，和灯光一起验证夜晚效果。"
  },
  animations: {
    title: "动画点",
    body: "放水车、旗帜、招牌、喷泉等循环动画锚点，后续绑定 SpriteFrames 或 AnimationPlayer。"
  },
  effects: {
    title: "特效",
    body: "放落叶、烟雾、萤火、雨雪等粒子区域或锚点，给天气和氛围层使用。"
  },
  audio: {
    title: "声音",
    body: "放环境声区域和点声源，比如河流、市场、人群、室内背景声。"
  },
  camera: {
    title: "镜头",
    body: "标镜头边界、热点和事件聚焦点，让运行时知道在哪些区域调整缩放和视角。"
  },
  semanticRegions: {
    title: "地点区域",
    body: "给 AI 居民理解自己在哪里、这里能做什么、隐私级别和默认行为。"
  }
};

const IMAGE_KIND_LABELS: Record<ImageKind, string> = {
  base: "整体预览",
  surface: "地表",
  object: "物件",
  foreground: "前景遮挡",
  reference: "参考"
};

const DEFAULT_IMAGE_KIND_VISIBLE: Record<ImageKind, boolean> = {
  base: true,
  surface: false,
  object: false,
  foreground: false,
  reference: false
};

const NAVIGATION_CELL_LABELS: Record<NavigationCellType, string> = {
  unknown: "未标注",
  walkable: "可通行",
  blocked: "阻挡",
  soft_blocked: "软阻挡",
  water: "水域",
  door: "门口"
};
const NAVIGATION_REGION_TYPES = NAVIGATION_CELL_TYPES.filter((type) => type !== "unknown") as NavigationRegionType[];

const NAV_COLORS: Record<string, string> = {
  walkable: "rgba(34, 197, 94, 0.48)",
  blocked: "rgba(239, 68, 68, 0.52)",
  soft_blocked: "rgba(245, 158, 11, 0.48)",
  water: "rgba(56, 189, 248, 0.5)",
  door: "rgba(168, 85, 247, 0.55)",
  unknown: "transparent"
};

export function App() {
  const [document, setDocument] = useState<MapToolDocument | null>(null);
  const [mapId, setMapId] = useState(DEFAULT_MAP_ID);
  const [diskHash, setDiskHash] = useState("");
  const [tool, setTool] = useState<ToolMode>("select");
  const [activeLayer, setActiveLayer] = useState<RuntimeLayerKind>("navigation");
  const [brushType, setBrushType] = useState<NavigationCellType>("walkable");
  const [brushSize, setBrushSize] = useState(1);
  const [selection, setSelection] = useState<MapToolSelection | null>(null);
  const [selectedVertexIndex, setSelectedVertexIndex] = useState<number | null>(null);
  const [status, setStatus] = useState("准备就绪");
  const [saveError, setSaveError] = useState("");
  const [forceSaveVisible, setForceSaveVisible] = useState(false);
  const [draftPoints, setDraftPoints] = useState<Point2[]>([]);
  const [history, setHistory] = useState<{ past: MapToolDocument[]; future: MapToolDocument[] }>({ past: [], future: [] });
  const [viewport, setViewport] = useState({ x: 48, y: 48, scale: 0.12 });
  const [dragging, setDragging] = useState(false);
  const [layerVisible, setLayerVisible] = useState<Record<RuntimeLayerKind, boolean>>(() => defaultLayerVisibility(true));
  const [layerLocked, setLayerLocked] = useState<Record<RuntimeLayerKind, boolean>>(() => Object.fromEntries(ALL_LAYERS.map((layer) => [layer, false])) as Record<RuntimeLayerKind, boolean>);
  const [imageKindVisible, setImageKindVisible] = useState<Record<ImageKind, boolean>>(DEFAULT_IMAGE_KIND_VISIBLE);
  const [packageManagerOpen, setPackageManagerOpen] = useState(false);
  const [packages, setPackages] = useState<PixelworkPackageSummary[]>([]);
  const [selectedSourceKey, setSelectedSourceKey] = useState("");
  const [sourceSearch, setSourceSearch] = useState("");
  const [sourcePathDraft, setSourcePathDraft] = useState("");
  const [packageLoading, setPackageLoading] = useState(false);
  const [jsonDraft, setJsonDraft] = useState("");
  const svgRef = useRef<SVGSVGElement | null>(null);
  const paintingRef = useRef(false);
  const panRef = useRef<{ x: number; y: number; startX: number; startY: number } | null>(null);
  const vertexDragRef = useRef<{ selection: MapToolSelection; vertexIndex: number; latestPoint?: Point2 } | null>(null);

  const validation = useMemo(() => document ? validateMapToolDocument(document) : { issues: [], canSync: false }, [document]);
  const selectedObject = useMemo(() => document && selection ? getObject(document, selection) : undefined, [document, selection]);
  const selectedPolygonPoints = useMemo(() => document && selection ? getPolygonPointsForSelection(document, selection) : null, [document, selection]);
  const selectedDraftObject = useMemo(() => parseJsonObject(jsonDraft), [jsonDraft]);
  const navCounts = useMemo(() => document ? navigationCounts(document) : null, [document]);
  const targetFieldKey = selection ? selectedTargetField(selection.layer) : "";
  const currentMode = workbenchModeFor(tool, activeLayer);
  const filteredSources = useMemo(() => filterMapSources(packages, sourceSearch), [packages, sourceSearch]);
  const groupedSources = useMemo(() => groupMapSources(filteredSources), [filteredSources]);
  const selectedSource = useMemo(() => packages.find((item) => sourceKey(item) === selectedSourceKey), [packages, selectedSourceKey]);

  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent) {
      const target = event.target as HTMLElement | null;
      if (target && ["INPUT", "TEXTAREA", "SELECT"].includes(target.tagName)) return;
      if (event.key === "Escape") {
        if (draftPoints.length > 0) {
          event.preventDefault();
          cancelDraftPolygon();
          return;
        }
        setSelectedVertexIndex(null);
        return;
      }
      if (event.key === "Backspace") {
        if (draftPoints.length > 0) {
          event.preventDefault();
          undoDraftPoint();
        }
        return;
      }
      if (event.key === "Enter") {
        if (draftPoints.length >= 3) {
          event.preventDefault();
          finishPolygon();
        }
        return;
      }
      if (event.key === "Delete") {
        if (selection && !isWholeNavigationSelection(selection)) {
          event.preventDefault();
          deleteSelected();
        }
      }
    }
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  });

  async function openPackageManager() {
    setPackageManagerOpen(true);
    await refreshPackageList();
  }

  async function refreshPackageList() {
    setPackageLoading(true);
    setSaveError("");
    try {
      const result = await listPixelworkPackages();
      setPackages(result.packages);
      const existingSelection = result.packages.find((item) => sourceKey(item) === selectedSourceKey);
      const currentEditableMap = result.packages.find((item) => item.sourceKind === "editable_map" && item.mapId === mapId);
      const defaultSelection = existingSelection ?? currentEditableMap ?? result.packages.find((item) => item.sourceKind === "editable_map") ?? result.packages.find((item) => item.sourceKind === "godot_scene") ?? result.packages.find((item) => item.sourceKind === "demo_scene") ?? result.packages.find((item) => item.packageRoot === result.defaultPackageRoot) ?? result.packages[0];
      setSelectedSourceKey(defaultSelection ? sourceKey(defaultSelection) : "");
      setSourcePathDraft(defaultSelection ? sourceDisplayPath(defaultSelection) : result.defaultPackageRoot ?? "");
      setStatus(`找到 ${result.packages.length} 个地图源`);
    } catch (error) {
      const message = error instanceof Error ? error.message : "地图源列表读取失败";
      setSaveError(message);
      setStatus("地图源列表读取失败");
    } finally {
      setPackageLoading(false);
    }
  }

  async function openSelectedSource(sourceOverride?: PixelworkPackageSummary) {
    const pickedSource = sourceOverride ?? selectedSource;
    if (pickedSource?.sourceKind === "editable_map") {
      await loadExistingMap(pickedSource.mapId ?? mapId);
      setPackageManagerOpen(false);
      return;
    }
    await importSelectedPixelwork(pickedSource);
  }

  async function importSelectedPixelwork(sourceOverride?: PixelworkPackageSummary) {
    const pickedSource = sourceOverride ?? selectedSource;
    const sourcePath = pickedSource ? sourceDisplayPath(pickedSource) : sourcePathDraft.trim();
    if (!sourcePath) {
      setSaveError("请先选择地图源");
      return;
    }
    setStatus("正在读取地图源");
    setSaveError("");
    const sourceKind = pickedSource?.sourceKind === "godot_scene" || pickedSource?.sourceKind === "demo_scene" || pickedSource?.sourceKind === "pixelwork_package" ? pickedSource.sourceKind : undefined;
    const result = await importPixelworkPackage({
      mapId,
      sourcePath,
      packageRoot: pickedSource?.packageRoot,
      sourceKind,
      scenePath: pickedSource?.scenePath
    });
    setDocument(result.document);
    setImageKindVisible(defaultImageKindVisibility(result.document));
    resetHistory();
    const existing = await loadMapToolDocument(result.document.mapId);
    setDiskHash(existing.hash);
    setSelection(null);
    setSelectedVertexIndex(null);
    setDraftPoints([]);
    setPackageManagerOpen(false);
    setStatus(`已导入 ${result.sourcePath}`);
  }

  async function browseMapSourceFolder() {
    setPackageLoading(true);
    setSaveError("");
    try {
      const result = await pickMapSourceFolder();
      if (result.cancelled || !result.source) {
        setStatus("已取消选择文件夹");
        return;
      }
      const nextSource = result.source;
      setPackages((current) => {
        const nextKey = sourceKey(nextSource);
        const withoutDuplicate = current.filter((item) => sourceKey(item) !== nextKey);
        return [nextSource, ...withoutDuplicate];
      });
      setSelectedSourceKey(sourceKey(nextSource));
      setSourcePathDraft(sourceDisplayPath(nextSource));
      setStatus(`已选择 ${nextSource.sourceLabel}：${nextSource.name}`);
    } catch (error) {
      const message = error instanceof Error ? error.message : "系统文件夹选择失败";
      setSaveError(message);
      setStatus("系统文件夹选择失败");
    } finally {
      setPackageLoading(false);
    }
  }

  async function loadExistingMap(nextMapId = mapId) {
    const safeMapId = nextMapId.trim();
    if (!safeMapId) return;
    setMapId(safeMapId);
    setStatus("正在刷新磁盘文件");
    setSaveError("");
    const result = await loadMapToolDocument(safeMapId);
    if (!result.exists || !result.document) {
      setStatus("当前 mapId 尚无 map_tool.json，可先从地图源管理器导入");
      setDiskHash(result.hash);
      return;
    }
    setDocument(result.document);
    setImageKindVisible(defaultImageKindVisibility(result.document));
    resetHistory();
    setDiskHash(result.hash);
    setSelection(null);
    setSelectedVertexIndex(null);
    setDraftPoints([]);
    setStatus(`已读取 ${result.mapPath}`);
  }

  async function saveCurrent(force = false) {
    if (!document) return;
    setStatus("正在保存并同步 Godot 文件");
    setSaveError("");
    setForceSaveVisible(false);
    try {
      const expectedHash = diskHash || (await loadMapToolDocument(document.mapId)).hash;
      const result = await saveMapToolDocument({
        document: stableMapToolDocument(document),
        expectedHash,
        force
      });
      setDocument(result.document);
      setDiskHash(result.hash);
      setStatus(`已同步 ${Object.keys(result.paths).length} 个文件`);
    } catch (error) {
      const message = error instanceof Error ? error.message : "保存失败";
      setSaveError(message);
      setForceSaveVisible(message.includes("磁盘文件已变化"));
      setStatus("保存失败");
    }
  }

  function updateDocument(mutator: (next: MapToolDocument) => void, options: { trackHistory?: boolean } = {}) {
    setDocument((current) => {
      if (!current) return current;
      const previous = clone(current);
      const next = clone(current);
      mutator(next);
      if (options.trackHistory !== false) {
        setHistory((currentHistory) => ({
          past: [...currentHistory.past, previous].slice(-MAX_HISTORY),
          future: []
        }));
      }
      return next;
    });
  }

  function resetHistory() {
    setHistory({ past: [], future: [] });
  }

  function undo() {
    if (!document || history.past.length === 0) return;
    const previous = history.past[history.past.length - 1];
    setHistory({
      past: history.past.slice(0, -1),
      future: [clone(document), ...history.future].slice(0, MAX_HISTORY)
    });
    setDocument(clone(previous));
    setSelection(null);
    setSelectedVertexIndex(null);
    setJsonDraft("");
    setStatus("已撤销");
  }

  function redo() {
    if (!document || history.future.length === 0) return;
    const next = history.future[0];
    setHistory({
      past: [...history.past, clone(document)].slice(-MAX_HISTORY),
      future: history.future.slice(1)
    });
    setDocument(clone(next));
    setSelection(null);
    setSelectedVertexIndex(null);
    setJsonDraft("");
    setStatus("已重做");
  }

  function canvasPoint(event: ReactPointerEvent<SVGSVGElement | SVGElement>): Point2 {
    const rect = svgRef.current!.getBoundingClientRect();
    return {
      x: Math.round((event.clientX - rect.left - viewport.x) / viewport.scale),
      y: Math.round((event.clientY - rect.top - viewport.y) / viewport.scale)
    };
  }

  function handleCanvasPointerDown(event: ReactPointerEvent<SVGSVGElement>) {
    if (!document) return;
    if (event.button === 1 || event.altKey) {
      event.preventDefault();
      event.stopPropagation();
      try {
        event.currentTarget.setPointerCapture(event.pointerId);
      } catch {
        // Some browsers reject capture for synthetic or already released pointers.
      }
      panRef.current = { x: viewport.x, y: viewport.y, startX: event.clientX, startY: event.clientY };
      setDragging(true);
      return;
    }
    const point = canvasPoint(event);
    if (event.button === 2) {
      event.preventDefault();
      if (tool === "polygon") finishPolygon();
      return;
    }
    if (tool === "select") {
      const vertex = findSelectedVertex(document, selection, point, 12 / viewport.scale);
      if (vertex) {
        if (layerLocked[vertex.selection.layer]) {
          setStatus(`${RUNTIME_LAYER_LABELS[vertex.selection.layer]}已锁定`);
          return;
        }
        beginVertexDrag(vertex.selection, vertex.vertexIndex);
        return;
      }
      const hit = findSelectableObjectAt(document, point, layerVisible, activeLayer);
      if (hit) {
        selectObject(hit.selection, hit.object);
        setSelectedVertexIndex(null);
        return;
      }
      setSelection(null);
      setSelectedVertexIndex(null);
      setJsonDraft("");
      return;
    }
    if (layerLocked[activeLayer]) {
      setStatus(`${RUNTIME_LAYER_LABELS[activeLayer]}已锁定`);
      return;
    }
    if (tool === "brush" && activeLayer === "navigation") {
      paintingRef.current = true;
      paintAt(point);
      return;
    }
    if (tool === "polygon" && POLYGON_LAYERS.includes(activeLayer as PolygonLayer)) {
      if (draftPoints.length >= 3 && distance(point, draftPoints[0]) <= 12 / viewport.scale) {
        finishPolygon();
        return;
      }
      setDraftPoints((current) => [...current, point]);
      setStatus(`绘制中：${draftPoints.length + 1} 个顶点。右键或 Enter 完成。`);
      return;
    }
    if (tool === "point" && POINT_LAYERS.includes(activeLayer as PointLayer)) {
      addPointLike(activeLayer as PointLayer, point);
      return;
    }
    if (tool === "erase") {
      eraseAt(point);
      return;
    }
  }

  function handlePointerMove(event: ReactPointerEvent<SVGSVGElement>) {
    if (vertexDragRef.current) {
      const drag = vertexDragRef.current;
      const point = canvasPoint(event);
      drag.latestPoint = point;
      updateDocument((next) => {
        updatePolygonVertex(next, drag.selection, drag.vertexIndex, point);
      }, { trackHistory: false });
      return;
    }
    if (panRef.current) {
      event.preventDefault();
      const dx = event.clientX - panRef.current.startX;
      const dy = event.clientY - panRef.current.startY;
      setViewport((current) => constrainViewport({ ...current, x: panRef.current!.x + dx, y: panRef.current!.y + dy }));
      return;
    }
    if (!paintingRef.current || tool !== "brush" || activeLayer !== "navigation") return;
    paintAt(canvasPoint(event));
  }

  function handlePointerUp(event?: ReactPointerEvent<SVGSVGElement>) {
    paintingRef.current = false;
    if (event && panRef.current) {
      event.preventDefault();
      try {
        event.currentTarget.releasePointerCapture(event.pointerId);
      } catch {
        // Pointer capture may already be gone when the browser cancels a drag.
      }
    }
    panRef.current = null;
    if (vertexDragRef.current) {
      const drag = vertexDragRef.current;
      const updated = document ? draftObjectWithMovedVertex(getObject(document, drag.selection), drag.vertexIndex, drag.latestPoint) : undefined;
      setJsonDraft(updated ? JSON.stringify(updated, null, 2) : "");
      setStatus("已移动顶点");
    }
    vertexDragRef.current = null;
    setDragging(false);
  }

  function handleWheel(event: WheelEvent<SVGSVGElement>) {
    event.preventDefault();
    const factor = event.deltaY < 0 ? 1.12 : 0.88;
    setViewport((current) => constrainViewport({
      ...current,
      scale: Math.max(0.04, Math.min(2, current.scale * factor))
    }));
  }

  function zoomCanvas(factor: number) {
    setViewport((current) => constrainViewport({
      ...current,
      scale: Math.max(0.04, Math.min(2, current.scale * factor))
    }));
  }

  function constrainViewport(next: typeof viewport): typeof viewport {
    const scale = clamp(Number.isFinite(next.scale) ? next.scale : viewport.scale, 0.04, 2);
    const fallback = {
      x: Number.isFinite(next.x) ? next.x : 48,
      y: Number.isFinite(next.y) ? next.y : 48,
      scale
    };
    if (!document || !svgRef.current) return fallback;
    const rect = svgRef.current.getBoundingClientRect();
    const scaledWidth = document.canvas.width * scale;
    const scaledHeight = document.canvas.height * scale;
    const slackX = Math.max(240, rect.width * 0.6);
    const slackY = Math.max(240, rect.height * 0.6);
    return {
      x: clamp(fallback.x, rect.width - scaledWidth - slackX, slackX),
      y: clamp(fallback.y, rect.height - scaledHeight - slackY, slackY),
      scale
    };
  }

  function fitCanvas() {
    if (!document || !svgRef.current) return;
    const rect = svgRef.current.getBoundingClientRect();
    const padding = 28;
    const scale = Math.max(0.04, Math.min(2, Math.min((rect.width - padding * 2) / document.canvas.width, (rect.height - padding * 2) / document.canvas.height)));
    setViewport({
      x: Math.round((rect.width - document.canvas.width * scale) / 2),
      y: Math.round((rect.height - document.canvas.height * scale) / 2),
      scale
    });
    setStatus("已适配画布");
  }

  function setWorkbenchMode(value: WorkbenchModeValue) {
    const mode = WORKBENCH_MODES.find((item) => item.value === value);
    if (!mode) return;
    setTool(mode.tool);
    setActiveLayer(mode.layer);
    if (mode.tool !== "polygon") {
      setDraftPoints([]);
    }
    setStatus(`已切换工具：${mode.label}`);
  }

  function activateLayer(layer: RuntimeLayerKind) {
    setActiveLayer(layer);
    if (layer === "navigation") {
      setTool("polygon");
    } else if (POLYGON_LAYERS.includes(layer as PolygonLayer)) {
      setTool("polygon");
    } else if (POINT_LAYERS.includes(layer as PointLayer)) {
      setTool("point");
    } else {
      setTool("select");
    }
    setSelectedVertexIndex(null);
    setStatus(`当前层：${RUNTIME_LAYER_LABELS[layer]}`);
  }

  function paintAt(point: Point2) {
    if (!document) return;
    const grid = document.layers.navigation;
    const cell = pointToCell(point, grid);
    const cells = cellsForBrush(cell.x, cell.y, brushSize, grid);
    updateDocument((next) => {
      next.layers.navigation = paintCells(next.layers.navigation, cells, brushType);
    });
  }

  function finishPolygon() {
    if (!document || draftPoints.length < 3 || !POLYGON_LAYERS.includes(activeLayer as PolygonLayer)) return;
    const id = nextId(document, activeLayer, layerPrefix(activeLayer));
    const object = makeDefaultPolygonObject(activeLayer, id, draftPoints[0]);
    object.shape = { type: "polygon", points: draftPoints };
    if (activeLayer === "navigation") {
      const navObject = object as NavigationRegionObject;
      navObject.type = navigationRegionTypeFor(brushType);
      navObject.debugColor = navigationColor(navObject.type);
      navObject.name = `新${NAVIGATION_CELL_LABELS[navObject.type]}区`;
    }
    updateDocument((next) => {
      editableItemsForLayer(next, activeLayer).push(object as { id: string });
    });
    setSelection({ layer: activeLayer, id });
    setSelectedVertexIndex(null);
    setDraftPoints([]);
    setStatus("已完成多边形");
  }

  function undoDraftPoint() {
    setDraftPoints((current) => current.slice(0, -1));
    setStatus("已撤回一个顶点");
  }

  function cancelDraftPolygon() {
    setDraftPoints([]);
    setStatus("已取消当前多边形");
  }

  function beginVertexDrag(nextSelection: MapToolSelection, vertexIndex: number) {
    if (!document) return;
    setHistory((currentHistory) => ({
      past: [...currentHistory.past, clone(document)].slice(-MAX_HISTORY),
      future: []
    }));
    vertexDragRef.current = { selection: nextSelection, vertexIndex };
    setSelection(nextSelection);
    setSelectedVertexIndex(vertexIndex);
    const object = getObject(document, nextSelection);
    setJsonDraft(object ? JSON.stringify(object, null, 2) : "");
    setDragging(true);
  }

  function addPointLike(layer: PointLayer, point: Point2) {
    if (!document) return;
    const id = nextId(document, layer, layerPrefix(layer));
    const object = makeDefaultPointObject(layer, id, point);
    updateDocument((next) => {
      (next.layers[layer] as unknown[]).push(object);
    });
    setSelection({ layer, id });
    setSelectedVertexIndex(null);
  }

  function eraseAt(point: Point2) {
    if (!document) return;
    if (activeLayer === "navigation") {
      const hitRegion = findNearestObject(document, activeLayer, point);
      if (hitRegion) {
        updateDocument((next) => {
          const items = editableItemsForLayer(next, activeLayer);
          const index = items.findIndex((item) => item.id === hitRegion.id);
          if (index >= 0) items.splice(index, 1);
        });
        if (selection?.layer === activeLayer && selection.id === hitRegion.id) {
          setSelection(null);
        }
        return;
      }
      const cell = pointToCell(point, document.layers.navigation);
      updateDocument((next) => {
        next.layers.navigation = paintCells(next.layers.navigation, [cell], "unknown");
      });
      return;
    }
    const hit = findNearestObject(document, activeLayer, point);
    if (!hit) return;
    updateDocument((next) => {
      const items = editableItemsForLayer(next, activeLayer);
      const index = items.findIndex((item) => item.id === hit.id);
      if (index >= 0) items.splice(index, 1);
    });
    if (selection?.layer === activeLayer && selection.id === hit.id) {
      setSelection(null);
    }
  }

  function selectObject(nextSelection: MapToolSelection, object: unknown) {
    setSelection(nextSelection);
    setSelectedVertexIndex(null);
    setJsonDraft(JSON.stringify(object, null, 2));
  }

  function applyJsonDraft() {
    if (!document || !selection) return;
    try {
      const parsed = JSON.parse(jsonDraft) as { id: string };
      if (!parsed.id) throw new Error("对象必须有 id");
      updateDocument((next) => {
        const items = editableItemsForLayer(next, selection.layer);
        const index = items.findIndex((item) => item.id === selection.id);
        if (index >= 0) {
          items[index] = parsed;
        }
      });
      setSelection({ layer: selection.layer, id: parsed.id });
      setStatus("对象 JSON 已应用");
    } catch (error) {
      setStatus(error instanceof Error ? error.message : "JSON 无法解析");
    }
  }

  function deleteSelected() {
    if (!document || !selection || isWholeNavigationSelection(selection)) return;
    if (layerLocked[selection.layer]) {
      setStatus(`${RUNTIME_LAYER_LABELS[selection.layer]}已锁定`);
      return;
    }
    updateDocument((next) => {
      const items = editableItemsForLayer(next, selection.layer);
      const index = items.findIndex((item) => item.id === selection.id);
      if (index >= 0) items.splice(index, 1);
    });
    setSelection(null);
    setSelectedVertexIndex(null);
    setJsonDraft("");
  }

  function duplicateSelected() {
    if (!document || !selection || isWholeNavigationSelection(selection)) return;
    if (layerLocked[selection.layer]) {
      setStatus(`${RUNTIME_LAYER_LABELS[selection.layer]}已锁定`);
      return;
    }
    const items = editableItemsForLayer(document, selection.layer) as Array<{ id: string; name?: string }>;
    const original = items.find((item) => item.id === selection.id);
    if (!original) return;
    const id = nextId(document, selection.layer, layerPrefix(selection.layer));
    const copied = offsetEditableObject(original, NUDGE_PIXELS, NUDGE_PIXELS);
    copied.id = id;
    if (typeof copied.name === "string") {
      copied.name = `${copied.name} 复制`;
    }
    updateDocument((next) => {
      (editableItemsForLayer(next, selection.layer) as Array<typeof copied>).push(copied);
    });
    setSelection({ layer: selection.layer, id });
    setSelectedVertexIndex(null);
    setJsonDraft(JSON.stringify(copied, null, 2));
    setStatus("已复制对象");
  }

  function moveSelected(dx: number, dy: number) {
    if (!document || !selection || isWholeNavigationSelection(selection)) return;
    if (layerLocked[selection.layer]) {
      setStatus(`${RUNTIME_LAYER_LABELS[selection.layer]}已锁定`);
      return;
    }
    const original = selectedObject;
    updateDocument((next) => {
      const items = editableItemsForLayer(next, selection.layer);
      const item = items.find((candidate) => candidate.id === selection.id);
      if (item) offsetGeometry(item, dx, dy);
    });
    if (original && typeof original === "object") {
      setJsonDraft(JSON.stringify(offsetEditableObject(original as { id: string }, dx, dy), null, 2));
    }
    setStatus("已移动对象");
  }

  function setAllLayersVisible(visible: boolean) {
    setLayerVisible(defaultLayerVisibility(visible));
  }

  function focusIssue(issue: ValidationIssue) {
    if (!issue.selection) return;
    setSelection(issue.selection);
    setSelectedVertexIndex(null);
    const object = document ? getObject(document, issue.selection) : undefined;
    setJsonDraft(object ? JSON.stringify(object, null, 2) : "");
  }

  function updateJsonDraftField(key: string, value: string | number) {
    const parsed = parseJsonObject(jsonDraft);
    if (!parsed) return;
    setJsonDraft(JSON.stringify({ ...parsed, [key]: value }, null, 2));
  }

  return (
    <main className="workbench-shell">
      <header className="app-header">
        <div className="app-brand">
          <div className="app-logo">Godot</div>
          <div>
            <strong>Godot 地图运行层编辑工具</strong>
            <span>{document ? `${document.displayName} · ${document.canvas.width} x ${document.canvas.height}` : "未打开地图"} · map_tool.json 保存后自动同步 Godot 运行文件</span>
          </div>
        </div>
        <div className="header-actions">
          <button type="button" onClick={() => void openPackageManager()} title="打开地图源管理器">
            <FolderOpen size={16} />
            <span>打开地图源</span>
          </button>
          <button type="button" onClick={() => void saveCurrent(false)} disabled={!document} title="保存 map_tool.json 并同步 runtime.json/layers.tscn">
            <Save size={16} />
            <span>保存同步</span>
          </button>
          {forceSaveVisible && (
            <button type="button" className="danger" onClick={() => void saveCurrent(true)} title="覆盖磁盘版本并同步">
              <FileDown size={16} />
              <span>确认覆盖</span>
            </button>
          )}
        </div>
      </header>
      <section className="workspace">
        <aside className="left-panel dock-sidebar">
          <section className="panel source-panel">
            <div className="panel-heading-inline">
              <h2>地图源与同步</h2>
              <small>{document ? sceneKindLabel(document) : "未加载"}</small>
            </div>
            <label className="dock-field">
              <span>mapId</span>
              <input value={mapId} onChange={(event) => setMapId(event.currentTarget.value)} />
            </label>
            <div className="source-actions">
              <button type="button" onClick={() => void openPackageManager()} title="打开地图源管理器">
                <FolderOpen size={15} />
                <span>打开源</span>
              </button>
              <button type="button" onClick={() => void loadExistingMap()} title="加载 generated/map_tool.json">
                <RefreshCw size={15} />
                <span>刷新文件</span>
              </button>
            </div>
            <article className="source-card">
              <div className="source-card-title">
                <strong>{document?.displayName ?? "未打开地图"}</strong>
                <code>{document?.mapId ?? mapId}</code>
              </div>
              <p>{document ? sourceSummary(document) : "选择 Godot Demo 场景或 Pixelwork 地图包，生成当前工具源数据。"}</p>
              {document ? (
                <div className="source-stats">
                  <span>图像 {layerCount(document, "images")}</span>
                  <span>通行 {layerCount(document, "navigation")}</span>
                  <span>碰撞 {layerCount(document, "collision")}</span>
                  <span>遮挡 {layerCount(document, "occlusion")}</span>
                  <span>点位/门 {runtimeObjectCount(document)}</span>
                </div>
              ) : (
                <code>{mapToolPath(mapId)}</code>
              )}
            </article>
            <div className="report-strip">
              <CheckCircle2 size={15} />
              <span>当前报错 {validation.issues.filter((issue) => issue.severity === "error").length}</span>
              <span>建议 {validation.issues.filter((issue) => issue.severity === "warning").length}</span>
            </div>
          </section>

          <section className="panel dock-section">
            <div className="panel-heading-inline">
              <h2>运行层工具</h2>
              <small>{WORKBENCH_MODES.find((mode) => mode.value === currentMode)?.label ?? "选择"}</small>
            </div>
            <div className="mode-grid">
              {QUICK_WORKBENCH_MODES.map((modeValue) => {
                const mode = WORKBENCH_MODES.find((item) => item.value === modeValue)!;
                return (
                  <button key={mode.value} type="button" className={currentMode === mode.value ? "is-active" : ""} onClick={() => setWorkbenchMode(mode.value)}>
                    {modeIcon(mode.value)}
                    <span>{mode.label.replace("多边形", "")}</span>
                  </button>
                );
              })}
            </div>
            <label className="dock-field subtle-field">
              <span>全部工具</span>
              <select value={currentMode} onChange={(event) => setWorkbenchMode(event.currentTarget.value as WorkbenchModeValue)}>
                {PRIMARY_WORKBENCH_MODES.map((mode) => (
                  <option key={mode.value} value={mode.value}>{mode.label}</option>
                ))}
              </select>
            </label>
            <div className="quick-toolbar">
              <button type="button" onClick={fitCanvas} disabled={!document} title="适配画布"><Maximize2 size={15} /><span>适配</span></button>
              <button type="button" onClick={undo} disabled={history.past.length === 0} title="撤销"><Undo2 size={15} /><span>撤销</span></button>
              <button type="button" onClick={redo} disabled={history.future.length === 0} title="重做"><Redo2 size={15} /><span>重做</span></button>
              <button type="button" className={tool === "erase" ? "is-active" : ""} onClick={() => setTool("erase")} disabled={!document} title="擦除对象或格子"><Eraser size={15} /><span>橡皮</span></button>
            </div>
            {activeLayer === "navigation" && (
              <div className="field-stack">
                <label>
                  <span>通行类型</span>
                  <select value={navigationRegionTypeFor(brushType)} onChange={(event) => setBrushType(event.currentTarget.value as NavigationCellType)}>
                    {NAVIGATION_REGION_TYPES.map((type) => <option key={type} value={type}>{NAVIGATION_CELL_LABELS[type]}</option>)}
                  </select>
                </label>
                <label>
                  <span>笔刷</span>
                  <select value={brushSize} onChange={(event) => setBrushSize(Number(event.currentTarget.value))}>
                    {[1, 2, 3, 5].map((size) => <option key={size} value={size}>{size} x {size}</option>)}
                  </select>
                </label>
              </div>
            )}
            {draftPoints.length > 0 && (
              <div className="draft-actions">
                <span>{draftPoints.length} 个顶点</span>
                <button type="button" onClick={finishPolygon} disabled={draftPoints.length < 3}>完成</button>
                <button type="button" onClick={undoDraftPoint}>撤点</button>
                <button type="button" onClick={cancelDraftPolygon}>取消</button>
              </div>
            )}
          </section>

          <section className="panel dock-section layer-panel">
            <div className="panel-heading-inline">
              <h2>运行层</h2>
              <div className="inline-actions">
                <button type="button" onClick={() => setAllLayersVisible(true)}>全显</button>
                <button type="button" onClick={() => setAllLayersVisible(false)}>全隐</button>
              </div>
            </div>
            {LAYER_GROUPS.map((group) => (
              <div key={group.title} className="layer-group">
                <strong>{group.title}</strong>
                <div className="layer-list">
                  {group.layers.map((layer) => (
                    <div key={layer} className={activeLayer === layer ? "layer-card is-active" : "layer-card"}>
                      <button type="button" className="layer-card-main" onClick={() => activateLayer(layer)}>
                        <span>{RUNTIME_LAYER_LABELS[layer]}</span>
                        <small>{layerCount(document, layer)}</small>
                      </button>
                      <button
                        type="button"
                        className={layerVisible[layer] ? "mini-toggle is-on" : "mini-toggle"}
                        title={layerVisible[layer] ? `隐藏${RUNTIME_LAYER_LABELS[layer]}` : `显示${RUNTIME_LAYER_LABELS[layer]}`}
                        onClick={() => setLayerVisible((current) => ({ ...current, [layer]: !current[layer] }))}
                      >
                        {layerVisible[layer] ? <Eye size={15} /> : <EyeOff size={15} />}
                      </button>
                      <button
                        type="button"
                        className={layerLocked[layer] ? "mini-toggle is-locked" : "mini-toggle"}
                        title={layerLocked[layer] ? `解锁${RUNTIME_LAYER_LABELS[layer]}` : `锁定${RUNTIME_LAYER_LABELS[layer]}`}
                        onClick={() => setLayerLocked((current) => ({ ...current, [layer]: !current[layer] }))}
                      >
                        {layerLocked[layer] ? <Lock size={15} /> : <Unlock size={15} />}
                      </button>
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </section>

          <section className="panel dock-section image-layer-panel">
            <div className="panel-heading-inline">
              <h2>图像子层</h2>
              <small>{layerVisible.images ? "已启用" : "总开关关闭"}</small>
            </div>
            {IMAGE_KINDS.map((kind) => (
              <button
                key={kind}
                type="button"
                className={imageKindVisible[kind] ? "image-kind-row is-visible" : "image-kind-row"}
                onClick={() => setImageKindVisible((current) => ({ ...current, [kind]: !current[kind] }))}
                disabled={!document}
                title={`${imageKindVisible[kind] ? "隐藏" : "显示"}${IMAGE_KIND_LABELS[kind]}`}
              >
                {imageKindVisible[kind] ? <Eye size={14} /> : <EyeOff size={14} />}
                <span>{IMAGE_KIND_LABELS[kind]}</span>
                <small>{imageKindCount(document, kind)}</small>
              </button>
            ))}
          </section>

          <section className="panel dock-section">
            <h2>选中属性</h2>
            <div className="selected-summary">{document && selection ? selectionSummary(document, selection) : "未选中"}</div>
            {selection && selectedObject && selectedDraftObject ? (
              <div className="field-stack compact-fields">
                <label>
                  <span>ID</span>
                  <input value={String(selectedDraftObject.id ?? "")} onChange={(event) => updateJsonDraftField("id", event.currentTarget.value)} />
                </label>
                <label>
                  <span>标签 / 名称</span>
                  <input value={String(selectedDraftObject.name ?? selectedDraftObject.label ?? "")} onChange={(event) => updateJsonDraftField("name", event.currentTarget.value)} />
                </label>
                {targetFieldKey && (
                  <label>
                    <span>目标</span>
                    <input value={String(selectedDraftObject[targetFieldKey] ?? "")} onChange={(event) => updateJsonDraftField(targetFieldKey, event.currentTarget.value)} />
                  </label>
                )}
                {selection.layer === "occlusion" && (
                  <label>
                    <span>baselineY</span>
                    <input type="number" value={Number(selectedDraftObject.baselineY ?? 0)} onChange={(event) => updateJsonDraftField("baselineY", Number(event.currentTarget.value))} />
                  </label>
                )}
                <button type="button" onClick={applyJsonDraft}>应用选中属性</button>
              </div>
            ) : (
              <div className="empty-compact">
                <MousePointer2 size={18} />
                <span>选择对象后编辑</span>
              </div>
            )}
          </section>

          <section className="panel dock-section help-panel">
            <h2>操作</h2>
            <p>左键加点；右键或 Enter 完成多边形。</p>
            <p>选择模式下点击多边形选中，拖白色顶点改形状。</p>
            <p>Alt/中键拖动画布，滚轮缩放，Delete 删除。</p>
          </section>

          <section className="panel dock-section">
            <h2>状态</h2>
            <p className="status-text">{status}</p>
            {saveError && <p className="error-text">{saveError}</p>}
            <div className={validation.canSync ? "sync-state ok" : "sync-state bad"}>
              {validation.canSync ? <CheckCircle2 size={15} /> : <XCircle size={15} />}
              <span>{validation.issues.filter((issue) => issue.severity === "error").length} 报错 · {validation.issues.filter((issue) => issue.severity === "warning").length} 建议</span>
            </div>
          </section>
        </aside>

        <section className={dragging ? "canvas-wrap is-dragging" : "canvas-wrap"}>
          <div className="canvas-toolbar">
            <button type="button" className="square-button" onClick={fitCanvas} disabled={!document} title="适配">
              <Maximize2 size={18} />
            </button>
            <div className="canvas-title">
              <strong>{document?.displayName ?? "未打开场景"}</strong>
              <span>{document ? `${document.canvas.width} x ${document.canvas.height} · 缩放 ${Math.round(viewport.scale * 100)}%` : "打开地图源后开始标注"}</span>
            </div>
            <div className="canvas-toolbar-actions">
              <button type="button" onClick={() => zoomCanvas(1 / 1.2)} title="缩小">
                <ZoomOut size={16} />
              </button>
              <button type="button" onClick={() => zoomCanvas(1.2)} title="放大">
                <ZoomIn size={16} />
              </button>
              <button type="button" onClick={fitCanvas} disabled={!document} title="自适应">
                <span>自适应</span>
              </button>
            </div>
          </div>
          <div className="canvas-stage">
            {!document ? (
              <div className="empty-state">
                <Download size={32} />
                <strong>先打开地图源或刷新 map_tool.json</strong>
              </div>
            ) : (
              <svg
                ref={svgRef}
                className="map-canvas"
                onPointerDown={handleCanvasPointerDown}
                onPointerMove={handlePointerMove}
                onPointerUp={handlePointerUp}
                onPointerLeave={handlePointerUp}
                onPointerCancel={handlePointerUp}
                onLostPointerCapture={handlePointerUp}
                onAuxClick={(event) => event.preventDefault()}
                onDragStart={(event) => event.preventDefault()}
                onContextMenu={(event) => {
                  event.preventDefault();
                  if (tool === "polygon") finishPolygon();
                }}
                onWheel={handleWheel}
              >
                <g transform={`translate(${viewport.x} ${viewport.y}) scale(${viewport.scale})`}>
                  <rect width={document.canvas.width} height={document.canvas.height} fill="#f7faf2" />
                  {layerVisible.images && renderImages(document.layers.images, imageKindVisible)}
                  {layerVisible.navigation && renderNavigation(document, selection, selectObject, tool === "select")}
                  {layerVisible.collision && renderPolygons(document.layers.collision, "collision", selection, selectObject, "#ef4444", tool === "select")}
                  {layerVisible.occlusion && renderPolygons(document.layers.occlusion, "occlusion", selection, selectObject, "#8b5cf6", tool === "select")}
                  {layerVisible.interactions && renderShapes(document.layers.interactions, "interactions", selection, selectObject, "#38bdf8", tool === "select")}
                  {layerVisible.lightOccluders && renderPolygons(document.layers.lightOccluders, "lightOccluders", selection, selectObject, "#facc15", tool === "select")}
                  {layerVisible.semanticRegions && renderShapes(document.layers.semanticRegions, "semanticRegions", selection, selectObject, "#22c55e", tool === "select")}
                  {layerVisible.doors && renderDoors(document.layers.doors, selection, selectObject, tool === "select")}
                  {layerVisible.points && renderPointObjects(document.layers.points, "points", selection, selectObject, "#ffffff", tool === "select")}
                  {layerVisible.lighting && renderPointObjects(document.layers.lighting, "lighting", selection, selectObject, "#ffd37a", tool === "select")}
                  {layerVisible.animations && renderPointObjects(document.layers.animations, "animations", selection, selectObject, "#fb7185", tool === "select")}
                  {layerVisible.effects && renderPointObjects(document.layers.effects, "effects", selection, selectObject, "#34d399", tool === "select")}
                  {layerVisible.audio && renderPointObjects(document.layers.audio, "audio", selection, selectObject, "#60a5fa", tool === "select")}
                  {layerVisible.camera && renderCamera(document.layers.camera, selection, selectObject, tool === "select")}
                  {draftPoints.length > 0 && (
                    <g pointerEvents="none">
                      <polyline
                        points={draftPoints.map((point) => `${point.x},${point.y}`).join(" ")}
                        fill="none"
                        stroke="#14532d"
                        strokeWidth={8 / viewport.scale}
                        strokeDasharray={`${16 / viewport.scale} ${12 / viewport.scale}`}
                      />
                      {draftPoints.map((point, index) => (
                        <circle key={`${point.x}-${point.y}-${index}`} cx={point.x} cy={point.y} r={13 / viewport.scale} fill="#ffffff" stroke="#14532d" strokeWidth={4 / viewport.scale} />
                      ))}
                    </g>
                  )}
                  {selection && selectedPolygonPoints && selectedPolygonPoints.length > 0 && tool === "select" && (
                    <g>
                      {selectedPolygonPoints.map((point, index) => (
                        <circle
                          key={`${selection.layer}-${selection.id}-vertex-${index}`}
                          cx={point.x}
                          cy={point.y}
                          r={(selectedVertexIndex === index ? 16 : 12) / viewport.scale}
                          fill={selectedVertexIndex === index ? "#fbbf24" : "#ffffff"}
                          stroke="#14532d"
                          strokeWidth={4 / viewport.scale}
                          onPointerDown={(event) => {
                            event.stopPropagation();
                            beginVertexDrag(selection, index);
                          }}
                        />
                      ))}
                    </g>
                  )}
                  <rect width={document.canvas.width} height={document.canvas.height} fill="none" stroke="#ffffff" strokeWidth={10 / viewport.scale} />
                </g>
              </svg>
            )}
            <div className="canvas-hint">左键加点/选择 · 右键或 Enter 完成多边形 · Backspace 撤点 · Esc 取消 · Alt 或中键拖动画布 · 滚轮缩放</div>
          </div>
        </section>

        <aside className="right-panel">
          <section className="panel right-section">
            <div className="panel-heading-inline">
              <h2>视图</h2>
              <small>自适应 · {Math.round(viewport.scale * 100)}%</small>
            </div>
            <input
              className="zoom-slider"
              type="range"
              min={4}
              max={200}
              value={Math.round(viewport.scale * 100)}
              onChange={(event) => setViewport((current) => constrainViewport({ ...current, scale: Number(event.currentTarget.value) / 100 }))}
            />
            <div className="view-actions">
              <button type="button" onClick={fitCanvas} disabled={!document}>适配</button>
              <button type="button" onClick={undo} disabled={history.past.length === 0}>撤销</button>
              <button type="button" onClick={redo} disabled={history.future.length === 0}>重做</button>
            </div>
          </section>

          <section className="panel right-section">
            <div className="panel-heading-inline">
              <h2>当前层工具</h2>
              <small>{RUNTIME_LAYER_LABELS[activeLayer]}</small>
            </div>
            <article className="layer-help">
              <strong>{LAYER_RUNTIME_HINTS[activeLayer].title}</strong>
              <span>{LAYER_RUNTIME_HINTS[activeLayer].body}</span>
            </article>
            {activeLayer === "navigation" ? (
              <>
                <div className="tool-toggle-row">
                  <button type="button" className={tool === "polygon" ? "is-active" : ""} onClick={() => setTool("polygon")}>
                    <PenLine size={16} />
                    <span>画区域</span>
                  </button>
                  <button type="button" className={tool === "brush" ? "is-active" : ""} onClick={() => setTool("brush")}>
                    <Brush size={16} />
                    <span>格刷</span>
                  </button>
                  <button type="button" className={tool === "erase" ? "is-active" : ""} onClick={() => setTool("erase")}>
                    <Eraser size={16} />
                    <span>擦除</span>
                  </button>
                  <button type="button" className={tool === "select" ? "is-active" : ""} onClick={() => setTool("select")}>
                    <MousePointer2 size={16} />
                    <span>选择</span>
                  </button>
                </div>
                <label className="right-field">
                  <span>通行类型</span>
                  <select value={navigationRegionTypeFor(brushType)} onChange={(event) => setBrushType(event.currentTarget.value as NavigationCellType)}>
                    {NAVIGATION_REGION_TYPES.map((type) => <option key={type} value={type}>{NAVIGATION_CELL_LABELS[type]}</option>)}
                  </select>
                </label>
                {tool === "brush" && (
                  <label className="right-field">
                    <span>格刷大小</span>
                    <select value={brushSize} onChange={(event) => setBrushSize(Number(event.currentTarget.value))}>
                      {[1, 2, 3, 5].map((size) => <option key={size} value={size}>{size} 格</option>)}
                    </select>
                  </label>
                )}
                <div className="polygon-tool-card">
                  <strong>{draftPoints.length > 0 ? `正在绘制 ${draftPoints.length} 个顶点` : `通行区域 ${(document?.layers.navigation.regions ?? []).length} 个`}</strong>
                  <span>左键加点，右键或 Enter 完成；格刷只用于兼容旧格子数据。</span>
                </div>
                <div className="view-actions">
                  <button type="button" onClick={finishPolygon} disabled={tool !== "polygon" || draftPoints.length < 3}>完成</button>
                  <button type="button" onClick={undoDraftPoint} disabled={tool !== "polygon" || draftPoints.length === 0}>撤点</button>
                  <button type="button" onClick={cancelDraftPolygon} disabled={tool !== "polygon" || draftPoints.length === 0}>取消</button>
                </div>
                <div className="stat-chips">
                  <span>多边形 {(document?.layers.navigation.regions ?? []).length}</span>
                  <span>旧格 {document?.layers.navigation.cellSize ?? 0}px · {document?.layers.navigation.width ?? 0} x {document?.layers.navigation.height ?? 0}</span>
                  <span>可行 {navCounts?.walkable ?? 0}</span>
                  <span>阻挡 {navCounts?.blocked ?? 0}</span>
                  <span>软阻 {navCounts?.soft_blocked ?? 0}</span>
                  <span>水域 {navCounts?.water ?? 0}</span>
                  <span>未填 {navCounts?.unknown ?? 0}</span>
                </div>
              </>
            ) : POLYGON_LAYERS.includes(activeLayer as PolygonLayer) ? (
              <>
                <div className="tool-toggle-row">
                  <button type="button" className={tool === "polygon" ? "is-active" : ""} onClick={() => setTool("polygon")}>
                    <PenLine size={16} />
                    <span>画多边形</span>
                  </button>
                  <button type="button" className={tool === "select" ? "is-active" : ""} onClick={() => setTool("select")}>
                    <MousePointer2 size={16} />
                    <span>改点</span>
                  </button>
                  <button type="button" className={tool === "erase" ? "is-active" : ""} onClick={() => setTool("erase")}>
                    <Eraser size={16} />
                    <span>擦除</span>
                  </button>
                </div>
                <div className="polygon-tool-card">
                  <strong>{draftPoints.length > 0 ? `正在绘制 ${draftPoints.length} 个顶点` : `${RUNTIME_LAYER_LABELS[activeLayer]}对象 ${layerCount(document, activeLayer)} 个`}</strong>
                  <span>左键加点，右键或 Enter 完成；选择模式可拖动顶点。</span>
                </div>
                <div className="view-actions">
                  <button type="button" onClick={finishPolygon} disabled={draftPoints.length < 3}>完成</button>
                  <button type="button" onClick={undoDraftPoint} disabled={draftPoints.length === 0}>撤点</button>
                  <button type="button" onClick={cancelDraftPolygon} disabled={draftPoints.length === 0}>取消</button>
                </div>
              </>
            ) : POINT_LAYERS.includes(activeLayer as PointLayer) ? (
              <>
                <div className="tool-toggle-row">
                  <button type="button" className={tool === "point" ? "is-active" : ""} onClick={() => setTool("point")}>
                    <Plus size={16} />
                    <span>放点</span>
                  </button>
                  <button type="button" className={tool === "select" ? "is-active" : ""} onClick={() => setTool("select")}>
                    <MousePointer2 size={16} />
                    <span>选择</span>
                  </button>
                  <button type="button" className={tool === "erase" ? "is-active" : ""} onClick={() => setTool("erase")}>
                    <Eraser size={16} />
                    <span>擦除</span>
                  </button>
                </div>
                <div className="polygon-tool-card">
                  <strong>{RUNTIME_LAYER_LABELS[activeLayer]}对象 {layerCount(document, activeLayer)} 个</strong>
                  <span>点击画布放置点位，选中后在属性区编辑具体字段。</span>
                </div>
              </>
            ) : (
              <div className="polygon-tool-card">
                <strong>{RUNTIME_LAYER_LABELS[activeLayer]}</strong>
                <span>图像层用于预览和对齐，显示细分在左侧“图像子层”中控制。</span>
              </div>
            )}
          </section>

          <section className="panel right-section inspector">
            <div className="panel-heading-inline">
              <h2>属性</h2>
              <small>{selection ? RUNTIME_LAYER_LABELS[selection.layer] : "未选中"}</small>
            </div>
            {selection && selectedObject ? (
              <>
                <div className="property-card">
                  <strong>{selectionSummary(document!, selection)}</strong>
                  <code>{selection.id}</code>
                </div>
                {!isWholeNavigationSelection(selection) && (
                  <div className="inspector-actions">
                    <button type="button" onClick={duplicateSelected} title="复制"><Copy size={15} /><span>复制</span></button>
                    <button type="button" className="icon-danger" onClick={deleteSelected} title="删除"><Trash2 size={15} /><span>删除</span></button>
                  </div>
                )}
                {!isWholeNavigationSelection(selection) && (
                  <div className="nudge-grid">
                    <button type="button" title="上移" onClick={() => moveSelected(0, -NUDGE_PIXELS)}><ArrowUp size={14} /></button>
                    <button type="button" title="左移" onClick={() => moveSelected(-NUDGE_PIXELS, 0)}><ArrowLeft size={14} /></button>
                    <button type="button" title="右移" onClick={() => moveSelected(NUDGE_PIXELS, 0)}><ArrowRight size={14} /></button>
                    <button type="button" title="下移" onClick={() => moveSelected(0, NUDGE_PIXELS)}><ArrowDown size={14} /></button>
                  </div>
                )}
                <textarea value={jsonDraft} onChange={(event) => setJsonDraft(event.currentTarget.value)} />
                <button type="button" onClick={applyJsonDraft}>应用 JSON</button>
              </>
            ) : (
              <div className="property-empty">
                <strong>没有选中对象</strong>
                <span>当前场景：{mapId}</span>
              </div>
            )}
          </section>

          <section className="panel right-section issue-panel">
            <h2>校验</h2>
            {validation.issues.length === 0 ? (
              <div className="empty-compact"><LocateFixed size={20} /><span>没有检查项</span></div>
            ) : validation.issues.map((issue, index) => (
              <button key={`${issue.message}-${index}`} type="button" className={`issue-row is-${issue.severity}`} onClick={() => focusIssue(issue)}>
                <strong>{issue.severity === "error" ? "报错" : "建议"}</strong>
                <span>{issue.message}</span>
                <small>{issue.suggestion}</small>
              </button>
            ))}
          </section>
        </aside>
      </section>
      {packageManagerOpen && (
        <div className="modal-backdrop" role="presentation">
          <section className="package-manager" role="dialog" aria-modal="true" aria-label="地图源管理器">
            <header>
              <div>
                <strong>地图管理器</strong>
                <span>{packages.length} 个地图条目</span>
              </div>
              <button type="button" onClick={() => setPackageManagerOpen(false)}>关闭</button>
            </header>
            <div className="package-toolbar">
              <label className="package-search">
                <Search size={16} />
                <input
                  value={sourceSearch}
                  onChange={(event) => setSourceSearch(event.currentTarget.value)}
                  placeholder="搜索地图名、mapId、场景或路径"
                />
              </label>
              <button type="button" onClick={() => void browseMapSourceFolder()} disabled={packageLoading}>浏览文件夹...</button>
              <button type="button" onClick={() => void refreshPackageList()} disabled={packageLoading}>刷新</button>
            </div>
            <div className="package-toolbar package-toolbar-secondary">
              <input
                value={sourcePathDraft}
                onChange={(event) => {
                  setSourcePathDraft(event.currentTarget.value);
                  setSelectedSourceKey("");
                }}
                placeholder="手动路径：game/world/prototypes/.../IndoorCafe.tscn 或 game/world/maps/pixelwork_map_stitch/..."
              />
              <button type="button" onClick={() => void openSelectedSource()} disabled={packageLoading || (!selectedSource && !sourcePathDraft.trim())}>
                {sourceActionLabel(selectedSource)}
              </button>
            </div>
            <div className="package-list">
              {groupedSources.map((group) => (
                <section key={group.kind} className="package-group">
                  <div className="package-group-heading">
                    <strong>{sourceKindLabel(group.kind)}</strong>
                    <span>{group.items.length}</span>
                  </div>
                  {group.items.map((item) => (
                    <article
                      key={sourceKey(item)}
                      className={sourceKey(item) === selectedSourceKey ? "package-row is-active" : "package-row"}
                    >
                      <button
                        type="button"
                        className="package-row-main"
                        onClick={() => {
                          setSelectedSourceKey(sourceKey(item));
                          setSourcePathDraft(sourceDisplayPath(item));
                        }}
                      >
                        <span>{item.name}</span>
                        <small>{item.canvas.width} x {item.canvas.height} · {sourceLayerSummary(item)}</small>
                        <small>{sourceMetaLine(item)}</small>
                        <code>{sourceDisplayPath(item)}</code>
                      </button>
                      <button
                        type="button"
                        className="package-row-action"
                        onClick={() => void openSelectedSource(item)}
                        disabled={packageLoading}
                      >
                        {item.sourceKind === "editable_map" ? "打开" : "导入"}
                      </button>
                    </article>
                  ))}
                </section>
              ))}
              {filteredSources.length === 0 && <div className="empty-compact">没有找到地图</div>}
            </div>
          </section>
        </div>
      )}
    </main>
  );
}

function workbenchModeFor(tool: ToolMode, layer: RuntimeLayerKind): WorkbenchModeValue {
  if (tool === "select") return "select";
  const match = WORKBENCH_MODES.find((mode) => mode.tool === tool && mode.layer === layer);
  return match?.value ?? "select";
}

function modeIcon(mode: WorkbenchModeValue) {
  if (mode === "select") return <MousePointer2 size={18} />;
  if (mode === "navigation") return <Brush size={18} />;
  if (mode === "doors") return <Layers size={18} />;
  if (mode === "lighting") return <Eye size={18} />;
  if (mode === "animations") return <RefreshCw size={18} />;
  if (mode === "points") return <LocateFixed size={18} />;
  if (mode === "semanticRegions") return <Map size={18} />;
  return <PenLine size={18} />;
}

function parseJsonObject(value: string): Record<string, unknown> | null {
  try {
    const parsed = JSON.parse(value) as unknown;
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed as Record<string, unknown> : null;
  } catch {
    return null;
  }
}

function selectedTargetField(layer: RuntimeLayerKind): string {
  const fields: Partial<Record<RuntimeLayerKind, string>> = {
    interactions: "targetId",
    doors: "toSceneId",
    semanticRegions: "linkedSceneId",
    points: "type",
    camera: "type",
    animations: "asset",
    effects: "preset",
    audio: "stream",
    lighting: "type"
  };
  return fields[layer] ?? "";
}

function sourceSummary(document: MapToolDocument): string {
  return document.source.demoScene ?? document.source.godotManifest ?? document.source.packageRoot ?? document.source.root;
}

function filterMapSources(sources: PixelworkPackageSummary[], query: string): PixelworkPackageSummary[] {
  const terms = query.trim().toLowerCase().split(/\s+/).filter(Boolean);
  if (terms.length === 0) return sources;
  return sources.filter((source) => {
    const haystack = sourceSearchText(source);
    return terms.every((term) => haystack.includes(term));
  });
}

function sourceSearchText(source: PixelworkPackageSummary): string {
  return [
    source.sourceLabel,
    source.sourceKind,
    source.name,
    source.mapId,
    source.mapPath,
    source.packageRoot,
    source.manifestPath,
    source.scenePath,
    source.layers.map((layer) => `${layer.id} ${layer.label}`).join(" ")
  ].filter(Boolean).join(" ").toLowerCase();
}

function groupMapSources(sources: PixelworkPackageSummary[]): Array<{ kind: SourceKind; items: PixelworkPackageSummary[] }> {
  const order: SourceKind[] = ["editable_map", "godot_scene", "demo_scene", "pixelwork_package"];
  return order
    .map((kind) => ({ kind, items: sources.filter((source) => source.sourceKind === kind) }))
    .filter((group) => group.items.length > 0);
}

function sourceKindLabel(kind: SourceKind): string {
  if (kind === "editable_map") return "已标记地图";
  if (kind === "godot_scene") return "Godot 场景地图";
  if (kind === "demo_scene") return "旧 Demo 场景";
  return "Pixelwork 原始包";
}

function sourceActionLabel(source: PixelworkPackageSummary | undefined): string {
  if (!source) return "按路径导入";
  return source.sourceKind === "editable_map" ? "打开标记地图" : "导入地图源";
}

function sourceLayerSummary(source: PixelworkPackageSummary): string {
  const visibleLayers = source.layers.filter((layer) => layer.tiles > 0);
  if (visibleLayers.length === 0) return "暂无标记层";
  return visibleLayers.slice(0, 7).map((layer) => `${layer.label} ${layer.tiles}`).join(" · ");
}

function sourceMetaLine(source: PixelworkPackageSummary): string {
  if (source.sourceKind === "editable_map") {
    return `${source.mapId ?? source.name} · ${formatModifiedTime(source.modifiedAt)}`;
  }
  if (source.scenePath) {
    return `场景：${source.scenePath}`;
  }
  return `原始包：${source.packageRoot ?? ""}`;
}

function formatModifiedTime(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString("zh-CN", {
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit"
  });
}

function sceneKindLabel(document: MapToolDocument): string {
  if (document.source.kind === "godot_scene") return "Godot 场景地图";
  if (document.source.demoScene) return "Godot Demo 场景";
  if (document.source.kind === "pixelwork_map_stitch") return "Pixelwork 地图包";
  return "手工场景";
}

function mapToolPath(mapId: string): string {
  return `game/world/maps/${mapId}/generated/map_tool.json`;
}

function runtimeObjectCount(document: MapToolDocument): number {
  return (
    document.layers.doors.length +
    document.layers.points.length
  );
}

function navigationCounts(document: MapToolDocument): Record<NavigationCellType, number> {
  const counts: Record<NavigationCellType, number> = {
    unknown: document.layers.navigation.width * document.layers.navigation.height,
    walkable: 0,
    blocked: 0,
    soft_blocked: 0,
    water: 0,
    door: 0
  };
  for (const cell of document.layers.navigation.cells) {
    counts.unknown = Math.max(0, counts.unknown - 1);
    counts[cell.type] += 1;
  }
  return counts;
}

function selectionSummary(document: MapToolDocument, selection: MapToolSelection): string {
  if (isWholeNavigationSelection(selection)) return "通行格子";
  const object = getObject(document, selection);
  if (!object || typeof object !== "object") return "未选中";
  const record = object as { id?: string; name?: string };
  return `${RUNTIME_LAYER_LABELS[selection.layer]}：${record.name ?? record.id ?? selection.id}`;
}

function renderImages(images: ImageLayer[], imageKindVisible: Record<ImageKind, boolean>) {
  return [...images]
    .filter((image) => image.visible && imageKindVisible[image.kind])
    .sort(compareImageDrawOrder)
    .map((image) => (
    <image
      key={image.id}
      href={localFileUrl(image.asset)}
      x={image.position.x}
      y={image.position.y}
      width={image.size.width}
      height={image.size.height}
      opacity={image.opacity}
      preserveAspectRatio="none"
    >
      <title>{IMAGE_KIND_LABELS[image.kind]} {image.tileKey ?? image.name}</title>
    </image>
  ));
}

function renderNavigation(
  document: MapToolDocument,
  selection: MapToolSelection | null,
  onSelect: (selection: MapToolSelection, object: unknown) => void,
  selectable = true
) {
  const grid = document.layers.navigation;
  const cells = grid.cells.filter((cell) => cell.type !== "unknown").map((cell) => (
    <rect
      key={`cell-${cell.x}-${cell.y}-${cell.type}`}
      x={cell.x * grid.cellSize}
      y={cell.y * grid.cellSize}
      width={grid.cellSize}
      height={grid.cellSize}
      fill={NAV_COLORS[cell.type]}
      stroke={selection?.layer === "navigation" && selection.id === "navigation" ? "#ffffff" : "transparent"}
      strokeWidth={2}
      pointerEvents={selectable ? "auto" : "none"}
      onPointerDown={(event) => {
        if (!selectable) return;
        event.stopPropagation();
        onSelect({ layer: "navigation", id: "navigation" }, cell);
      }}
    />
  ));
  const regions = (grid.regions ?? []).map((region) => (
    <polygon
      key={region.id}
      points={region.shape.points.map((point) => `${point.x},${point.y}`).join(" ")}
      fill={`${region.debugColor ?? navigationColor(region.type)}66`}
      stroke={selection?.layer === "navigation" && selection.id === region.id ? "#ffffff" : region.debugColor ?? navigationColor(region.type)}
      strokeWidth={selection?.layer === "navigation" && selection.id === region.id ? 8 : 4}
      pointerEvents={selectable ? "auto" : "none"}
      onPointerDown={(event) => {
        if (!selectable) return;
        event.stopPropagation();
        onSelect({ layer: "navigation", id: region.id }, region);
      }}
    />
  ));
  return [...cells, ...regions];
}

function renderPolygons<T extends { id: string; shape: PolygonShape }>(
  objects: T[],
  layer: RuntimeLayerKind,
  selection: MapToolSelection | null,
  onSelect: (selection: MapToolSelection, object: unknown) => void,
  color: string,
  selectable = true
) {
  return objects.map((object) => (
    <polygon
      key={object.id}
      points={object.shape.points.map((point) => `${point.x},${point.y}`).join(" ")}
      fill={`${color}55`}
      stroke={selection?.layer === layer && selection.id === object.id ? "#ffffff" : color}
      strokeWidth={selection?.layer === layer && selection.id === object.id ? 8 : 4}
      pointerEvents={selectable ? "auto" : "none"}
      onPointerDown={(event) => {
        if (!selectable) return;
        event.stopPropagation();
        onSelect({ layer, id: object.id }, object);
      }}
    />
  ));
}

function renderShapes<T extends { id: string; shape: Shape }>(
  objects: T[],
  layer: RuntimeLayerKind,
  selection: MapToolSelection | null,
  onSelect: (selection: MapToolSelection, object: unknown) => void,
  color: string,
  selectable = true
) {
  return objects.map((object) => {
    const common = {
      fill: `${color}44`,
      stroke: selection?.layer === layer && selection.id === object.id ? "#ffffff" : color,
      strokeWidth: selection?.layer === layer && selection.id === object.id ? 8 : 4,
      pointerEvents: selectable ? "auto" : "none",
      onPointerDown: (event: ReactPointerEvent<SVGElement>) => {
        if (!selectable) return;
        event.stopPropagation();
        onSelect({ layer, id: object.id }, object);
      }
    };
    if (object.shape.type === "circle") {
      return <circle key={object.id} cx={object.shape.x} cy={object.shape.y} r={object.shape.radius} {...common} />;
    }
    if (object.shape.type === "rect") {
      return <rect key={object.id} x={object.shape.x} y={object.shape.y} width={object.shape.width} height={object.shape.height} {...common} />;
    }
    return <polygon key={object.id} points={object.shape.points.map((point) => `${point.x},${point.y}`).join(" ")} {...common} />;
  });
}

function renderPointObjects<T extends { id: string; position: Point2 }>(
  objects: T[],
  layer: RuntimeLayerKind,
  selection: MapToolSelection | null,
  onSelect: (selection: MapToolSelection, object: unknown) => void,
  color: string,
  selectable = true
) {
  return objects.map((object) => (
    <g
      key={object.id}
      transform={`translate(${object.position.x} ${object.position.y})`}
      pointerEvents={selectable ? "auto" : "none"}
      onPointerDown={(event) => {
        if (!selectable) return;
        event.stopPropagation();
        onSelect({ layer, id: object.id }, object);
      }}
    >
      <circle r={selection?.layer === layer && selection.id === object.id ? 26 : 18} fill={color} stroke="#111827" strokeWidth={4} />
      <line x1={0} y1={-28} x2={0} y2={28} stroke="#111827" strokeWidth={3} />
      <line x1={-28} y1={0} x2={28} y2={0} stroke="#111827" strokeWidth={3} />
    </g>
  ));
}

function renderDoors(objects: DoorObject[], selection: MapToolSelection | null, onSelect: (selection: MapToolSelection, object: unknown) => void, selectable = true) {
  return objects.map((door) => (
    <g
      key={door.id}
      transform={`translate(${door.fromPoint.x} ${door.fromPoint.y})`}
      pointerEvents={selectable ? "auto" : "none"}
      onPointerDown={(event) => {
        if (!selectable) return;
        event.stopPropagation();
        onSelect({ layer: "doors", id: door.id }, door);
      }}
    >
      <rect x={-22} y={-28} width={44} height={56} rx={8} fill="#a855f7" stroke={selection?.layer === "doors" && selection.id === door.id ? "#ffffff" : "#111827"} strokeWidth={5} />
    </g>
  ));
}

function renderCamera(objects: Array<{ id: string; targetPoint: Point2; shape: Shape }>, selection: MapToolSelection | null, onSelect: (selection: MapToolSelection, object: unknown) => void, selectable = true) {
  return objects.map((camera) => (
    <g
      key={camera.id}
      pointerEvents={selectable ? "auto" : "none"}
      onPointerDown={(event) => {
        if (!selectable) return;
        event.stopPropagation();
        onSelect({ layer: "camera", id: camera.id }, camera);
      }}
    >
      <circle cx={camera.targetPoint.x} cy={camera.targetPoint.y} r={34} fill="#f472b6" stroke={selection?.layer === "camera" && selection.id === camera.id ? "#ffffff" : "#111827"} strokeWidth={5} />
    </g>
  ));
}

function getObject(document: MapToolDocument, selection: MapToolSelection): unknown {
  if (selection.layer === "navigation") {
    if (selection.id === "navigation") return document.layers.navigation;
    return (document.layers.navigation.regions ?? []).find((item) => item.id === selection.id);
  }
  return (document.layers[selection.layer] as Array<{ id: string }>).find((item) => item.id === selection.id);
}

function getPolygonPointsForSelection(document: MapToolDocument, selection: MapToolSelection): Point2[] | null {
  const object = getObject(document, selection);
  const shape = objectShape(object);
  return shape?.type === "polygon" ? shape.points : null;
}

function updatePolygonVertex(document: MapToolDocument, selection: MapToolSelection, vertexIndex: number, point: Point2): void {
  const item = (editableItemsForLayer(document, selection.layer) as Array<{ id: string; shape?: Shape }>).find((candidate) => candidate.id === selection.id);
  if (!item || item.shape?.type !== "polygon" || vertexIndex < 0 || vertexIndex >= item.shape.points.length) return;
  item.shape.points[vertexIndex] = { x: Math.round(point.x), y: Math.round(point.y) };
  if (selection.layer === "occlusion" && "baselineY" in item && typeof item.baselineY !== "number") {
    item.baselineY = maxPointY(item.shape.points);
  }
}

function draftObjectWithMovedVertex(object: unknown, vertexIndex: number, point: Point2 | undefined): unknown {
  if (!point || !object || typeof object !== "object") return object;
  const copied = clone(object);
  const shape = objectShape(copied);
  if (shape?.type === "polygon" && vertexIndex >= 0 && vertexIndex < shape.points.length) {
    shape.points[vertexIndex] = { x: Math.round(point.x), y: Math.round(point.y) };
  }
  return copied;
}

function findSelectedVertex(document: MapToolDocument, selection: MapToolSelection | null, point: Point2, threshold: number): { selection: MapToolSelection; vertexIndex: number } | null {
  if (!selection) return null;
  const points = getPolygonPointsForSelection(document, selection);
  if (!points) return null;
  let bestIndex = -1;
  let bestDistance = threshold;
  for (let index = 0; index < points.length; index += 1) {
    const candidateDistance = distance(points[index], point);
    if (candidateDistance < bestDistance) {
      bestDistance = candidateDistance;
      bestIndex = index;
    }
  }
  return bestIndex >= 0 ? { selection, vertexIndex: bestIndex } : null;
}

function findSelectableObjectAt(
  document: MapToolDocument,
  point: Point2,
  layerVisible: Record<RuntimeLayerKind, boolean>,
  activeLayer: RuntimeLayerKind
): { selection: MapToolSelection; object: unknown } | null {
  const layerOrder = selectableLayerOrder(activeLayer);
  for (const layer of layerOrder) {
    if (!layerVisible[layer]) continue;
    const items = editableItemsForLayer(document, layer) as Array<{ id: string; position?: Point2; fromPoint?: Point2; targetPoint?: Point2; shape?: Shape }>;
    for (let index = items.length - 1; index >= 0; index -= 1) {
      const item = items[index];
      if (objectContainsPoint(item, point)) {
        return { selection: { layer, id: item.id }, object: item };
      }
    }
  }
  return null;
}

function selectableLayerOrder(activeLayer: RuntimeLayerKind): RuntimeLayerKind[] {
  const baseOrder: RuntimeLayerKind[] = [
    "navigation",
    "doors",
    "interactions",
    "semanticRegions",
    "lightOccluders",
    "occlusion",
    "collision",
    "points",
    "lighting",
    "animations",
    "effects",
    "audio",
    "camera"
  ];
  if (baseOrder.includes(activeLayer)) {
    return [activeLayer, ...baseOrder.filter((layer) => layer !== activeLayer)];
  }
  return baseOrder;
}

function objectContainsPoint(object: { position?: Point2; fromPoint?: Point2; targetPoint?: Point2; shape?: Shape }, point: Point2): boolean {
  if (object.shape && shapeContainsPoint(object.shape, point)) return true;
  const anchor = object.position ?? object.fromPoint ?? object.targetPoint;
  return anchor ? distance(anchor, point) <= 64 : false;
}

function shapeContainsPoint(shape: Shape, point: Point2): boolean {
  if (shape.type === "circle") {
    return distance({ x: shape.x, y: shape.y }, point) <= shape.radius;
  }
  if (shape.type === "rect") {
    return point.x >= shape.x && point.y >= shape.y && point.x <= shape.x + shape.width && point.y <= shape.y + shape.height;
  }
  return pointInPolygon(point, shape.points);
}

function pointInPolygon(point: Point2, polygon: Point2[]): boolean {
  if (polygon.length < 3) return false;
  let inside = false;
  let j = polygon.length - 1;
  for (let i = 0; i < polygon.length; i += 1) {
    const pi = polygon[i];
    const pj = polygon[j];
    let denominator = pj.y - pi.y;
    if (Math.abs(denominator) < 0.0001) {
      denominator = denominator >= 0 ? 0.0001 : -0.0001;
    }
    if ((pi.y > point.y) !== (pj.y > point.y) && point.x < ((pj.x - pi.x) * (point.y - pi.y)) / denominator + pi.x) {
      inside = !inside;
    }
    j = i;
  }
  return inside;
}

function objectShape(object: unknown): Shape | undefined {
  if (!object || typeof object !== "object") return undefined;
  const maybeShape = (object as { shape?: Shape }).shape;
  return maybeShape;
}

function distance(a: Point2, b: Point2): number {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

function maxPointY(points: Point2[]): number {
  return points.reduce((max, point) => Math.max(max, point.y), points[0]?.y ?? 0);
}

function findNearestObject(document: MapToolDocument, layer: RuntimeLayerKind, point: Point2): { id: string } | null {
  if (layer === "images") return null;
  const items = editableItemsForLayer(document, layer) as Array<{ id: string; position?: Point2; fromPoint?: Point2; targetPoint?: Point2; shape?: Shape }>;
  let best: { id: string; distance: number } | null = null;
  for (const item of items) {
    if (item.shape && shapeContainsPoint(item.shape, point)) {
      return { id: item.id };
    }
    const anchor = item.position ?? item.fromPoint ?? item.targetPoint ?? shapeAnchor(item.shape);
    if (!anchor) continue;
    const distance = Math.hypot(anchor.x - point.x, anchor.y - point.y);
    if (distance < 80 && (!best || distance < best.distance)) {
      best = { id: item.id, distance };
    }
  }
  return best ? { id: best.id } : null;
}

function shapeAnchor(shape: Shape | undefined): Point2 | undefined {
  if (!shape) return undefined;
  if (shape.type === "circle") return { x: shape.x, y: shape.y };
  if (shape.type === "rect") return { x: shape.x + shape.width / 2, y: shape.y + shape.height / 2 };
  if (shape.points.length === 0) return undefined;
  return {
    x: shape.points.reduce((sum, point) => sum + point.x, 0) / shape.points.length,
    y: shape.points.reduce((sum, point) => sum + point.y, 0) / shape.points.length
  };
}

function offsetEditableObject<T extends object>(object: T, dx: number, dy: number): T {
  const copied = clone(object);
  offsetGeometry(copied, dx, dy);
  return copied;
}

function offsetGeometry(value: unknown, dx: number, dy: number): void {
  if (Array.isArray(value)) {
    for (const item of value) {
      offsetGeometry(item, dx, dy);
    }
    return;
  }
  if (!value || typeof value !== "object") return;

  const record = value as Record<string, unknown>;
  if (typeof record.x === "number" && typeof record.y === "number") {
    record.x += dx;
    record.y += dy;
  }
  for (const key of Object.keys(record)) {
    if (key === "id" || key === "name" || key === "tags") continue;
    offsetGeometry(record[key], dx, dy);
  }
}

function layerCount(document: MapToolDocument | null, layer: RuntimeLayerKind): number {
  if (!document) return 0;
  if (layer === "navigation") return (document.layers.navigation.regions ?? []).length;
  return (document.layers[layer] as unknown[]).length;
}

function defaultLayerVisibility(visible: boolean): Record<RuntimeLayerKind, boolean> {
  return Object.fromEntries(ALL_LAYERS.map((layer) => [layer, visible && !ADVANCED_LAYERS.includes(layer)])) as Record<RuntimeLayerKind, boolean>;
}

function editableItemsForLayer(document: MapToolDocument, layer: RuntimeLayerKind): Array<{ id: string }> {
  if (layer === "navigation") {
    document.layers.navigation.regions = document.layers.navigation.regions ?? [];
    return document.layers.navigation.regions as Array<{ id: string }>;
  }
  return document.layers[layer] as Array<{ id: string }>;
}

function isWholeNavigationSelection(selection: MapToolSelection): boolean {
  return selection.layer === "navigation" && selection.id === "navigation";
}

function navigationRegionTypeFor(type: NavigationCellType): NavigationRegionType {
  return type === "unknown" ? "walkable" : type;
}

function navigationColor(type: string): string {
  if (type === "walkable") return "#22c55e";
  if (type === "blocked") return "#ef4444";
  if (type === "soft_blocked") return "#f59e0b";
  if (type === "water") return "#38bdf8";
  if (type === "door") return "#a855f7";
  return "#94a3b8";
}

function clamp(value: number, min: number, max: number): number {
  const lower = Math.min(min, max);
  const upper = Math.max(min, max);
  const safe = Number.isFinite(value) ? value : 0;
  return Math.max(lower, Math.min(upper, safe));
}

function imageKindCount(document: MapToolDocument | null, kind: ImageKind): number {
  if (!document) return 0;
  return document.layers.images.filter((image) => image.kind === kind).length;
}

function defaultImageKindVisibility(document: MapToolDocument): Record<ImageKind, boolean> {
  const hasBase = document.layers.images.some((image) => image.kind === "base");
  if (hasBase) {
    return { ...DEFAULT_IMAGE_KIND_VISIBLE };
  }
  return {
    base: false,
    surface: true,
    object: true,
    foreground: true,
    reference: false
  };
}

function compareImageDrawOrder(a: ImageLayer, b: ImageLayer): number {
  const kindOrder: Record<ImageKind, number> = {
    base: 0,
    surface: 10,
    object: 20,
    foreground: 30,
    reference: 40
  };
  if (kindOrder[a.kind] !== kindOrder[b.kind]) return kindOrder[a.kind] - kindOrder[b.kind];
  if (a.zIndex !== b.zIndex) return a.zIndex - b.zIndex;
  return a.id.localeCompare(b.id);
}

function sourceKey(source: PixelworkPackageSummary): string {
  if (source.sourceKind === "editable_map") {
    return `${source.sourceKind}:${source.mapId ?? source.mapPath ?? source.name}`;
  }
  return `${source.sourceKind}:${source.scenePath ?? source.packageRoot}`;
}

function sourceDisplayPath(source: PixelworkPackageSummary): string {
  if (source.sourceKind === "editable_map") {
    return source.mapPath ?? mapToolPath(source.mapId ?? source.name);
  }
  if ((source.sourceKind === "godot_scene" || source.sourceKind === "demo_scene") && source.scenePath) {
    return source.scenePath.replace(/\/[^/]+\.tscn$/i, "");
  }
  return source.packageRoot ?? "";
}

function layerPrefix(layer: RuntimeLayerKind): string {
  const prefix: Record<RuntimeLayerKind, string> = {
    images: "img",
    navigation: "nav",
    collision: "col",
    occlusion: "occ",
    interactions: "hit",
    doors: "door",
    points: "point",
    lighting: "light",
    lightOccluders: "light_occ",
    animations: "anim",
    effects: "fx",
    audio: "audio",
    camera: "cam",
    semanticRegions: "semantic"
  };
  return prefix[layer];
}
