import crypto from "node:crypto";
import { execFile } from "node:child_process";
import fs from "node:fs/promises";
import fsSync from "node:fs";
import type { Dirent } from "node:fs";
import type { IncomingMessage, ServerResponse } from "node:http";
import path from "node:path";
import type { Plugin } from "vite";
import { exportSplitRuntimeFiles } from "../exporters/runtime";
import { exportLayersTscn } from "../exporters/tscn";
import { importPixelworkPackage, type PixelworkAnnotations, type PixelworkManifest } from "../importers/pixelwork";
import { stableJson } from "../model/hash";
import { createEmptyMapDocument, stableMapToolDocument } from "../model/mapDocument";
import type { CollisionLayerObject, ImageLayer, MapToolDocument, OcclusionObject, Point2, PointObject, PolygonShape } from "../model/types";
import {
  DEFAULT_PIXELWORK_ENDPOINT,
  FILE_ENDPOINT,
  IMPORT_PIXELWORK_ENDPOINT,
  LIST_PIXELWORK_ENDPOINT,
  LOAD_MAP_ENDPOINT,
  PICK_MAP_SOURCE_FOLDER_ENDPOINT,
  SAVE_MAP_ENDPOINT
} from "../shared/endpoints";

const MAX_REQUEST_BYTES = 30 * 1024 * 1024;
const DEFAULT_PIXELWORK_ROOT =
  "game/world/maps/pixelwork_map_stitch/2026-07-08T07-57-31-361Z_20260708_161838_873";
const HIDDEN_MAP_IDS = new Set(["town_art_pipeline_demo"]);

type MapSourceKind = "editable_map" | "godot_scene" | "demo_scene" | "pixelwork_package";

interface MapSourceSummary {
  sourceKind: MapSourceKind;
  sourceLabel: string;
  packageRoot?: string;
  manifestPath?: string;
  scenePath?: string;
  mapId?: string;
  mapPath?: string;
  name: string;
  canvas: { width: number; height: number };
  layers: Array<{ id: string; label: string; tiles: number }>;
  modifiedAt: string;
}

class MapWorkbenchInputError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "MapWorkbenchInputError";
  }
}

export function createLocalMapWorkbenchPlugin({ repoRoot }: { repoRoot: string }): Plugin {
  return {
    name: "huazi-godot-map-workbench",
    configureServer(server) {
      server.middlewares.use(DEFAULT_PIXELWORK_ENDPOINT, async (req, res, next) => {
        if (req.method !== "GET") {
          next();
          return;
        }
        try {
          const packageRoot = DEFAULT_PIXELWORK_ROOT;
          const manifestPath = await findGodotManifest(repoRoot, packageRoot);
          sendJson(res, 200, { ok: true, packageRoot, manifestPath });
        } catch (error) {
          sendError(res, error);
        }
      });

      server.middlewares.use(LIST_PIXELWORK_ENDPOINT, async (req, res, next) => {
        if (req.method !== "GET") {
          next();
          return;
        }
        try {
          sendJson(res, 200, {
            ok: true,
            packages: await listPixelworkPackages(repoRoot),
            defaultPackageRoot: DEFAULT_PIXELWORK_ROOT
          });
        } catch (error) {
          sendError(res, error);
        }
      });

      server.middlewares.use(PICK_MAP_SOURCE_FOLDER_ENDPOINT, async (req, res, next) => {
        if (req.method !== "POST") {
          next();
          return;
        }
        try {
          const selectedPath = await pickFolderWithWindowsDialog(repoRoot);
          if (!selectedPath) {
            sendJson(res, 200, { ok: true, cancelled: true });
            return;
          }
          const source = await mapSourceFromSelectedFolder(repoRoot, selectedPath);
          sendJson(res, 200, { ok: true, cancelled: false, source });
        } catch (error) {
          sendError(res, error);
        }
      });

      server.middlewares.use(IMPORT_PIXELWORK_ENDPOINT, async (req, res, next) => {
        if (req.method !== "POST") {
          next();
          return;
        }
        try {
          const body = await readJsonBody(req) as {
            mapId?: unknown;
            sourcePath?: unknown;
            packageRoot?: unknown;
            sourceKind?: unknown;
            scenePath?: unknown;
          };
          const mapId = safeMapId(body.mapId);
          const resolvedSource = typeof body.sourcePath === "string" && body.sourcePath
            ? await mapSourceFromSelectedFolder(repoRoot, body.sourcePath)
            : undefined;
          const requestedScenePath = typeof body.scenePath === "string" && body.scenePath
            ? safeGodotScenePath(repoRoot, body.scenePath)
            : undefined;
          if (resolvedSource?.sourceKind === "godot_scene" || requestedScenePath || body.sourceKind === "godot_scene") {
            const scenePath = resolvedSource?.scenePath ?? requestedScenePath;
            if (!scenePath) throw new MapWorkbenchInputError("缺少 Godot 场景路径");
            const document = await importGodotPrototypeScene(repoRoot, mapId, scenePath);
            sendJson(res, 200, {
              ok: true,
              document,
              sourceKind: "godot_scene",
              scenePath,
              sourcePath: scenePath
            });
            return;
          }
          const packageRoot = resolvedSource?.packageRoot ?? safePixelworkRoot(typeof body.packageRoot === "string" && body.packageRoot ? body.packageRoot : DEFAULT_PIXELWORK_ROOT);
          const scenePath = resolvedSource?.scenePath ?? (
            typeof body.scenePath === "string" && body.scenePath
              ? safeGodotScenePath(repoRoot, body.scenePath)
              : undefined
          );
          const sourceKind = scenePath ? "demo_scene" : "pixelwork_package";
          const manifestPath = await findGodotManifest(repoRoot, packageRoot);
          const manifest = await readJsonFile<PixelworkManifest>(path.join(repoRoot, manifestPath));
          const annotations = manifest.annotations_file
            ? await readOptionalJsonFile<PixelworkAnnotations>(path.join(repoRoot, packageRoot, manifest.annotations_file))
            : undefined;
          const document = importPixelworkPackage({
            mapId,
            displayName: mapId,
            manifest,
            annotations,
            packageRoot,
            demoScenePath: scenePath
          });
          if (scenePath) {
            await importDemoSceneRuntimeSpecs(repoRoot, scenePath, document);
          }
          const nextDocument = stableMapToolDocument(document);
          sendJson(res, 200, {
            ok: true,
            document: nextDocument,
            packageRoot,
            sourceKind,
            scenePath,
            sourcePath: scenePath ?? packageRoot
          });
        } catch (error) {
          sendError(res, error);
        }
      });

      server.middlewares.use(LOAD_MAP_ENDPOINT, async (req, res, next) => {
        if (req.method !== "GET") {
          next();
          return;
        }
        try {
          const url = new URL(req.url ?? "", "http://localhost");
          const mapId = safeMapId(url.searchParams.get("mapId"));
          const mapPath = generatedPath(repoRoot, mapId, "map_tool.json");
          const raw = await readOptionalText(mapPath);
          if (!raw) {
            sendJson(res, 200, { ok: true, exists: false, hash: "", mapPath: repoRelative(repoRoot, mapPath) });
            return;
          }
          sendJson(res, 200, {
            ok: true,
            exists: true,
            document: JSON.parse(raw),
            hash: hashText(raw),
            mapPath: repoRelative(repoRoot, mapPath)
          });
        } catch (error) {
          sendError(res, error);
        }
      });

      server.middlewares.use(SAVE_MAP_ENDPOINT, async (req, res, next) => {
        if (req.method !== "POST") {
          next();
          return;
        }
        try {
          const body = await readJsonBody(req) as {
            document?: unknown;
            expectedHash?: unknown;
            force?: unknown;
          };
          assertMapToolDocument(body.document);
          const document = stableMapToolDocument(body.document);
          const expectedHash = typeof body.expectedHash === "string" ? body.expectedHash : "";
          const force = body.force === true;
          const result = await saveAndSyncMap({ repoRoot, document, expectedHash, force });
          sendJson(res, 200, result);
        } catch (error) {
          sendError(res, error);
        }
      });

      server.middlewares.use(FILE_ENDPOINT, async (req, res, next) => {
        if (req.method !== "GET") {
          next();
          return;
        }
        try {
          const url = new URL(req.url ?? "", "http://localhost");
          const value = url.searchParams.get("path");
          if (!value) throw new MapWorkbenchInputError("缺少 path");
          const filePath = resolveWorkbenchAssetPath(repoRoot, value);
          const stream = fsSync.createReadStream(filePath);
          res.setHeader("Content-Type", contentTypeForPath(filePath));
          stream.on("error", (error) => sendError(res, error));
          stream.pipe(res);
        } catch (error) {
          sendError(res, error);
        }
      });
    }
  };
}

export async function saveAndSyncMap({
  repoRoot,
  document,
  expectedHash,
  force = false
}: {
  repoRoot: string;
  document: MapToolDocument;
  expectedHash: string;
  force?: boolean;
}): Promise<{ ok: true; hash: string; paths: Record<string, string>; document: MapToolDocument }> {
  const mapPath = generatedPath(repoRoot, document.mapId, "map_tool.json");
  await fs.mkdir(path.dirname(mapPath), { recursive: true });
  const currentRaw = await readOptionalText(mapPath);
  const currentHash = currentRaw ? hashText(currentRaw) : "";
  if (!force && currentHash !== expectedHash) {
    throw new MapWorkbenchInputError("磁盘文件已变化，请先刷新再保存，或确认覆盖。");
  }

  const nextDocument = stableMapToolDocument({
    ...document,
    fileState: {
      ...document.fileState,
      lastLoadedHash: expectedHash,
      lastSavedAt: new Date().toISOString()
    }
  });
  const serializedDocument = stableJson(nextDocument);
  await writeTextAtomic(mapPath, serializedDocument);

  const splitFiles = exportSplitRuntimeFiles(nextDocument);
  const paths: Record<string, string> = {
    "map_tool.json": repoRelative(repoRoot, mapPath)
  };
  for (const [filename, value] of Object.entries(splitFiles)) {
    const filePath = generatedPath(repoRoot, document.mapId, filename);
    await writeTextAtomic(filePath, stableJson(value));
    paths[filename] = repoRelative(repoRoot, filePath);
  }

  const tscnPath = generatedPath(repoRoot, document.mapId, "layers.tscn");
  await writeTextAtomic(tscnPath, exportLayersTscn(nextDocument));
  paths["layers.tscn"] = repoRelative(repoRoot, tscnPath);

  return {
    ok: true,
    hash: hashText(serializedDocument),
    paths,
    document: nextDocument
  };
}

async function findGodotManifest(repoRoot: string, packageRoot: string): Promise<string> {
  const root = resolveRepoPath(repoRoot, packageRoot);
  const entries = await fs.readdir(root);
  const manifest = entries.find((entry) => entry.endsWith("_godot.json"));
  if (!manifest) {
    throw new MapWorkbenchInputError(`找不到 Godot manifest：${packageRoot}`);
  }
  return repoRelative(repoRoot, path.join(root, manifest));
}

async function listPixelworkPackages(repoRoot: string): Promise<MapSourceSummary[]> {
  const packages: MapSourceSummary[] = [];
  packages.unshift(...await listPrototypeSceneSources(repoRoot));
  packages.unshift(...await listEditableMapSources(repoRoot));
  const editableMapIds = new Set(packages.filter((item) => item.sourceKind === "editable_map" && item.mapId).map((item) => item.mapId));
  return packages.filter((item) => item.sourceKind !== "godot_scene" || !item.mapId || !editableMapIds.has(item.mapId)).sort((a, b) => {
    const kindOrder: Record<MapSourceKind, number> = {
      editable_map: 0,
      godot_scene: 1,
      demo_scene: 2,
      pixelwork_package: 3
    };
    if (a.sourceKind !== b.sourceKind) return kindOrder[a.sourceKind] - kindOrder[b.sourceKind];
    return b.modifiedAt.localeCompare(a.modifiedAt);
  });
}

async function listEditableMapSources(repoRoot: string): Promise<MapSourceSummary[]> {
  const mapsRoot = resolveRepoPath(repoRoot, "game/world/maps");
  const mapToolPaths = await collectGeneratedMapToolFiles(mapsRoot, 0, 5);
  const summaries: MapSourceSummary[] = [];
  for (const mapToolPath of mapToolPaths) {
    try {
      const document = await readJsonFile<MapToolDocument>(mapToolPath);
      if (HIDDEN_MAP_IDS.has(document.mapId)) continue;
      const stat = await fs.stat(mapToolPath);
      summaries.push({
        sourceKind: "editable_map",
        sourceLabel: "已标记地图",
        mapId: document.mapId,
        mapPath: repoRelative(repoRoot, mapToolPath),
        packageRoot: document.source.packageRoot,
        manifestPath: document.source.godotManifest,
        scenePath: document.source.demoScene,
        name: document.displayName || document.mapId,
        canvas: {
          width: document.canvas.width,
          height: document.canvas.height
        },
        layers: mapToolLayerSummaries(document),
        modifiedAt: stat.mtime.toISOString()
      });
    } catch {
      // Ignore broken generated files in the picker; validation happens when a map is opened.
    }
  }
  return summaries;
}

async function collectGeneratedMapToolFiles(dir: string, depth: number, maxDepth: number): Promise<string[]> {
  if (depth > maxDepth) return [];
  let entries: Dirent[];
  try {
    entries = await fs.readdir(dir, { withFileTypes: true });
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return [];
    throw error;
  }

  const files: string[] = [];
  const hasGeneratedMapTool = entries.some((entry) => entry.isFile() && entry.name === "map_tool.json")
    && path.basename(dir) === "generated";
  if (hasGeneratedMapTool) {
    files.push(path.join(dir, "map_tool.json"));
    return files;
  }

  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    files.push(...await collectGeneratedMapToolFiles(path.join(dir, entry.name), depth + 1, maxDepth));
  }
  return files;
}

function mapToolLayerSummaries(document: MapToolDocument): Array<{ id: string; label: string; tiles: number }> {
  return [
    { id: "images", label: "图像", tiles: document.layers.images.length },
    { id: "navigation", label: "通行", tiles: (document.layers.navigation.regions ?? []).length + document.layers.navigation.cells.length },
    { id: "collision", label: "碰撞", tiles: document.layers.collision.length },
    { id: "occlusion", label: "遮挡", tiles: document.layers.occlusion.length },
    { id: "interactions", label: "交互", tiles: document.layers.interactions.length },
    { id: "doors", label: "门", tiles: document.layers.doors.length },
    { id: "lighting", label: "灯光", tiles: document.layers.lighting.length }
  ];
}

async function collectPixelworkPackages(
  repoRoot: string,
  dir: string,
  packages: MapSourceSummary[],
  depth: number
): Promise<void> {
  if (depth > 2) return;
  let entries: Dirent[];
  try {
    entries = await fs.readdir(dir, { withFileTypes: true });
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return;
    throw error;
  }

  const manifestEntry = entries.find((entry) => entry.isFile() && entry.name.endsWith("_godot.json"));
  if (manifestEntry) {
    const manifestPath = path.join(dir, manifestEntry.name);
    packages.push(await pixelworkSourceSummary(repoRoot, dir, manifestPath));
    return;
  }

  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    await collectPixelworkPackages(repoRoot, path.join(dir, entry.name), packages, depth + 1);
  }
}

async function pickFolderWithWindowsDialog(repoRoot: string): Promise<string | undefined> {
  const selected = await runPowerShellFolderPicker(repoRoot);
  if (!selected) return undefined;
  const absolutePath = path.resolve(selected);
  const relative = path.relative(repoRoot, absolutePath);
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new MapWorkbenchInputError("选择的文件夹必须位于当前项目目录内");
  }
  return repoRelative(repoRoot, absolutePath);
}

function runPowerShellFolderPicker(repoRoot: string): Promise<string | undefined> {
  const script = `
Add-Type -AssemblyName System.Windows.Forms
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$dialog = New-Object System.Windows.Forms.FolderBrowserDialog
$dialog.Description = '选择 Godot 地图源文件夹'
$dialog.SelectedPath = '${escapePowerShellSingleQuoted(repoRoot)}'
$dialog.ShowNewFolderButton = $false
$result = $dialog.ShowDialog()
if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
  Write-Output $dialog.SelectedPath
}
`;
  return new Promise((resolve, reject) => {
    execFile("powershell.exe", ["-NoProfile", "-STA", "-Command", script], {
      encoding: "utf8",
      windowsHide: false,
      timeout: 5 * 60 * 1000
    }, (error, stdout, stderr) => {
      if (error) {
        reject(new MapWorkbenchInputError(stderr.trim() || error.message || "无法打开系统文件夹选择器"));
        return;
      }
      const selected = stdout.trim();
      resolve(selected || undefined);
    });
  });
}

async function mapSourceFromSelectedFolder(repoRoot: string, selectedFolder: string): Promise<MapSourceSummary> {
  const absoluteSelection = resolveRepoPath(repoRoot, selectedFolder);
  const selectionStat = await fs.stat(absoluteSelection);
  if (selectionStat.isFile()) {
    if (absoluteSelection.endsWith("_godot.json")) {
      return pixelworkSourceSummary(repoRoot, path.dirname(absoluteSelection), absoluteSelection);
    }
    if (absoluteSelection.endsWith(".tscn")) {
      const sceneSource = await prototypeSceneSummary(repoRoot, absoluteSelection);
      if (sceneSource) return sceneSource;
    }
    throw new MapWorkbenchInputError("这个文件不是可识别的地图源：请选择 .tscn 场景文件或 _godot.json。");
  }

  const absoluteFolder = absoluteSelection;
  const entries = await fs.readdir(absoluteFolder, { withFileTypes: true });
  const manifestEntry = entries.find((entry) => entry.isFile() && entry.name.endsWith("_godot.json"));
  if (manifestEntry) {
    const manifestPath = path.join(absoluteFolder, manifestEntry.name);
    return pixelworkSourceSummary(repoRoot, absoluteFolder, manifestPath);
  }

  const sceneEntry = entries.find((entry) => entry.isFile() && entry.name.endsWith(".tscn"));
  if (sceneEntry) {
    const scenePath = path.join(absoluteFolder, sceneEntry.name);
    const sceneSource = await prototypeSceneSummary(repoRoot, scenePath);
    if (sceneSource) return sceneSource;
    const scriptPath = scenePath.replace(/\.tscn$/i, ".gd");
    if (fsSync.existsSync(scriptPath)) {
      const demoSource = await demoSourceSummaryFromScript(repoRoot, scriptPath);
      if (demoSource) return demoSource;
    }
  }

  throw new MapWorkbenchInputError("这个路径不是可识别的地图源：请选择 .tscn 场景文件、包含 .tscn/.gd 的 Godot 地图场景文件夹，或包含 _godot.json 的 Pixelwork 包。");
}

async function pixelworkSourceSummary(repoRoot: string, dir: string, manifestPath: string): Promise<MapSourceSummary> {
  const manifest = await readJsonFile<PixelworkManifest>(manifestPath);
  const stat = await fs.stat(manifestPath);
  return {
    sourceKind: "pixelwork_package",
    sourceLabel: "Pixelwork 原始包",
    packageRoot: repoRelative(repoRoot, dir),
    manifestPath: repoRelative(repoRoot, manifestPath),
    name: path.basename(dir),
    canvas: {
      width: manifest.canvas?.width ?? 0,
      height: manifest.canvas?.height ?? 0
    },
    layers: layerSummaries(manifest),
    modifiedAt: stat.mtime.toISOString()
  };
}

async function listPrototypeSceneSources(repoRoot: string): Promise<MapSourceSummary[]> {
  const prototypeRoot = resolveRepoPath(repoRoot, "game/world/prototypes");
  const scenes = await collectFilesByExt(prototypeRoot, ".tscn", 0, 4);
  const summaries: MapSourceSummary[] = [];
  const seen = new Set<string>();
  for (const scenePath of scenes) {
    const summary = await prototypeSceneSummary(repoRoot, scenePath);
    if (!summary?.scenePath) continue;
    if (seen.has(summary.scenePath)) continue;
    seen.add(summary.scenePath);
    summaries.push(summary);
  }
  return summaries;
}

async function listPrototypeDemoSources(repoRoot: string): Promise<MapSourceSummary[]> {
  const prototypeRoot = resolveRepoPath(repoRoot, "game/world/prototypes");
  const scripts = await collectFilesByExt(prototypeRoot, ".gd", 0, 4);
  const summaries: MapSourceSummary[] = [];
  const seen = new Set<string>();
  for (const scriptPath of scripts) {
    const summary = await demoSourceSummaryFromScript(repoRoot, scriptPath);
    if (!summary) continue;
    const packageRoot = summary.packageRoot;
    if (!packageRoot) continue;
    if (seen.has(packageRoot)) continue;
    seen.add(packageRoot);
    summaries.push(summary);
  }
  return summaries;
}

async function demoSourceSummaryFromScript(repoRoot: string, scriptPath: string): Promise<MapSourceSummary | undefined> {
  const scriptText = await fs.readFile(scriptPath, "utf8");
  const match = scriptText.match(/manifest_path\s*:=\s*"([^"]+_godot\.json)"/);
  if (!match) return undefined;

  const manifestRepoPath = godotResourceToRepoRelative(match[1]);
  if (!manifestRepoPath) return undefined;
  const manifestPath = resolveRepoPath(repoRoot, manifestRepoPath);
  const packageRoot = repoRelative(repoRoot, path.dirname(manifestPath));
  const manifest = await readJsonFile<PixelworkManifest>(manifestPath);
  const scenePath = await siblingScenePath(repoRoot, scriptPath);
  const stat = await fs.stat(scenePath ? resolveRepoPath(repoRoot, scenePath) : scriptPath);
  return {
    sourceKind: "demo_scene",
    sourceLabel: "可运行 Demo 场景",
    packageRoot,
    manifestPath: repoRelative(repoRoot, manifestPath),
    scenePath,
    name: scenePath ? path.basename(scenePath, ".tscn") : path.basename(scriptPath, ".gd"),
    canvas: {
      width: manifest.canvas?.width ?? 0,
      height: manifest.canvas?.height ?? 0
    },
    layers: layerSummaries(manifest),
    modifiedAt: stat.mtime.toISOString()
  };
}

function layerSummaries(manifest: PixelworkManifest): Array<{ id: string; label: string; tiles: number }> {
  return (manifest.layers ?? []).map((layer) => ({
    id: layer.id,
    label: layer.label,
    tiles: layer.tiles?.length ?? 0
  }));
}

async function collectFilesByExt(dir: string, ext: string, depth: number, maxDepth: number): Promise<string[]> {
  if (depth > maxDepth) return [];
  let entries: Dirent[];
  try {
    entries = await fs.readdir(dir, { withFileTypes: true });
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return [];
    throw error;
  }
  const files: string[] = [];
  for (const entry of entries) {
    const childPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      const childFiles = await collectFilesByExt(childPath, ext, depth + 1, maxDepth);
      files.push(...childFiles);
    } else if (entry.isFile() && entry.name.endsWith(ext)) {
      files.push(childPath);
    }
  }
  return files;
}

async function siblingScenePath(repoRoot: string, scriptPath: string): Promise<string | undefined> {
  const candidate = scriptPath.replace(/\.gd$/i, ".tscn");
  try {
    await fs.access(candidate);
    return repoRelative(repoRoot, candidate);
  } catch {
    return undefined;
  }
}

async function prototypeSceneSummary(repoRoot: string, scenePath: string): Promise<MapSourceSummary | undefined> {
  const sceneRepoPath = repoRelative(repoRoot, scenePath);
  if (!sceneRepoPath.startsWith("game/world/prototypes/")) return undefined;
  const info = await prototypeSceneInfo(repoRoot, sceneRepoPath);
  if (!info) return undefined;
  const stat = await fs.stat(scenePath);
  return {
    sourceKind: "godot_scene",
    sourceLabel: "Godot 场景地图",
    mapId: mapIdFromScenePath(sceneRepoPath),
    scenePath: sceneRepoPath,
    name: path.basename(sceneRepoPath, ".tscn"),
    canvas: info.canvas,
    layers: [
      { id: "images", label: "底图", tiles: 1 + info.repairPatches.length },
      { id: "collision", label: "碰撞", tiles: info.collisionRects.length },
      { id: "occlusion", label: "遮挡", tiles: info.occlusionPolygons.length }
    ],
    modifiedAt: stat.mtime.toISOString()
  };
}

function mapIdFromScenePath(scenePath: string): string {
  const folder = path.basename(path.dirname(scenePath));
  const sceneName = path.basename(scenePath, ".tscn");
  const normalizedSceneName = toSnakeCase(sceneName);
  const normalizedFolder = folder.replace(/[^A-Za-z0-9_-]+/g, "_").toLowerCase();
  if (normalizedSceneName === normalizedFolder) return safeMapId(folder.replace(/[^A-Za-z0-9_-]+/g, "_"));
  return safeMapId(`${folder}_${normalizedSceneName}`.replace(/[^A-Za-z0-9_-]+/g, "_"));
}

function toSnakeCase(value: string): string {
  return value
    .replace(/([a-z0-9])([A-Z])/g, "$1_$2")
    .replace(/([A-Z]+)([A-Z][a-z])/g, "$1_$2")
    .replace(/([A-Za-z])([0-9])/g, "$1_$2")
    .replace(/([0-9])([A-Za-z])/g, "$1_$2")
    .replace(/[^A-Za-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .toLowerCase();
}

function godotResourceToRepoRelative(value: string): string | undefined {
  if (!value.startsWith("res://")) return undefined;
  return `game/${value.slice("res://".length)}`;
}

interface PrototypeSceneInfo {
  scenePath: string;
  scriptPath?: string;
  canvas: { width: number; height: number };
  mapImagePath: string;
  mapImagePosition?: { x: number; y: number };
  repairPatches: PrototypeImagePatch[];
  collisionRects: PrototypeRectSpec[];
  occlusionPolygons: DemoShapeSpec[];
  points: PrototypePointSpec[];
}

interface PrototypeImagePatch {
  path: string;
  position: { x: number; y: number };
  size?: { width: number; height: number };
}

interface PrototypeRectSpec {
  id: string;
  rect: { x: number; y: number; width: number; height: number };
}

interface PrototypePointSpec {
  id: string;
  name: string;
  position: Point2;
}

interface ScriptText {
  repoPath: string;
  text: string;
}

export async function importGodotPrototypeScene(repoRoot: string, mapId: string, scenePath: string): Promise<MapToolDocument> {
  const info = await prototypeSceneInfo(repoRoot, scenePath);
  if (!info) {
    throw new MapWorkbenchInputError(`无法从 Godot 场景读取地图底图：${scenePath}`);
  }
  const document = createEmptyMapDocument(mapId, mapId, info.canvas.width, info.canvas.height);
  document.source = {
    kind: "godot_scene",
    root: scenePath,
    demoScene: scenePath
  };
  document.layers.images = await prototypeImageLayers(repoRoot, info);
  document.layers.collision = info.collisionRects.map((spec, index) => rectCollision(spec, index));
  document.layers.occlusion = info.occlusionPolygons.map((spec) => polygonOcclusion(spec));
  document.layers.points = info.points.map((spec) => pointObject(spec));
  return stableMapToolDocument(document);
}

async function prototypeSceneInfo(repoRoot: string, scenePath: string): Promise<PrototypeSceneInfo | undefined> {
  const sceneText = await fs.readFile(resolveRepoPath(repoRoot, scenePath), "utf8");
  const scriptPath = scriptPathFromScene(sceneText);
  if (scriptPath) {
    try {
      const scripts = await readScriptChain(repoRoot, scriptPath);
      const mapImagePath = firstStringConstant(scripts, ["MAP_PATH", "MAP_TEXTURE_PATH"]);
      const mapRepoPath = mapImagePath ? godotResourceToRepoRelative(mapImagePath) : undefined;
      if (mapRepoPath) {
        const parsedSize = firstVectorConstant(scripts, ["MAP_SIZE"]);
        const imageSize = await imageDimensions(resolveRepoPath(repoRoot, mapRepoPath));
        const canvas = parsedSize
          ? { width: Math.round(parsedSize.x), height: Math.round(parsedSize.y) }
          : { width: imageSize.width, height: imageSize.height };
        return {
          scenePath,
          scriptPath,
          canvas,
          mapImagePath: mapRepoPath,
          repairPatches: parseRepairPatches(scripts),
          collisionRects: parseCollisionRects(scripts),
          occlusionPolygons: parsePrototypeOcclusionPolygons(scripts),
          points: []
        };
      }
    } catch {
      // Fall back to reading the scene file directly.
    }
  }
  return prototypeSceneInfoFromTscn(repoRoot, scenePath, sceneText);
}

async function prototypeSceneInfoFromTscn(repoRoot: string, scenePath: string, sceneText: string): Promise<PrototypeSceneInfo | undefined> {
  const blocks = parseTscnBlocks(sceneText);
  const extResources = tscnExtResources(blocks);
  const nodes = tscnNodes(blocks);
  const sprite = nodes
    .filter((node) => node.type === "Sprite2D" && extResourceId(node.props.get("texture") ?? ""))
    .sort((a, b) => spritePriority(b.name) - spritePriority(a.name))[0];
  if (!sprite) return undefined;

  const textureId = extResourceId(sprite.props.get("texture") ?? "");
  const texturePath = textureId ? extResources.get(textureId)?.path : undefined;
  const mapRepoPath = texturePath ? godotResourceToRepoRelative(texturePath) : undefined;
  if (!mapRepoPath) return undefined;

  const imageSize = await imageDimensions(resolveRepoPath(repoRoot, mapRepoPath));
  const scale = parseVector2(sprite.props.get("scale") ?? "") ?? { x: 1, y: 1 };
  const canvas = {
    width: Math.round(imageSize.width * Math.abs(scale.x || 1)),
    height: Math.round(imageSize.height * Math.abs(scale.y || 1))
  };
  const spritePosition = globalNodePosition(sprite, nodes);
  const spriteOffset = parseVector2(sprite.props.get("offset") ?? "") ?? { x: 0, y: 0 };
  const centered = (sprite.props.get("centered") ?? "true") !== "false";
  const imageTopLeft = centered
    ? { x: spritePosition.x - canvas.width / 2 + spriteOffset.x, y: spritePosition.y - canvas.height / 2 + spriteOffset.y }
    : { x: spritePosition.x + spriteOffset.x, y: spritePosition.y + spriteOffset.y };
  const sceneToCanvas = { x: -imageTopLeft.x, y: -imageTopLeft.y };

  return {
    scenePath,
    canvas,
    mapImagePath: mapRepoPath,
    mapImagePosition: { x: 0, y: 0 },
    repairPatches: [],
    collisionRects: collisionRectsFromTscn(blocks, nodes, sceneToCanvas),
    occlusionPolygons: [],
    points: markerPointsFromTscn(nodes, sceneToCanvas)
  };
}

interface TscnBlock {
  header: string;
  kind: string;
  attrs: Record<string, string>;
  props: Map<string, string>;
}

interface TscnNode {
  name: string;
  type: string;
  parent: string;
  path: string;
  props: Map<string, string>;
}

function parseTscnBlocks(sceneText: string): TscnBlock[] {
  const blocks: TscnBlock[] = [];
  let current: TscnBlock | undefined;
  for (const rawLine of sceneText.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line) continue;
    if (line.startsWith("[") && line.endsWith("]")) {
      if (current) blocks.push(current);
      const kind = line.match(/^\[([A-Za-z_]+)/)?.[1] ?? "";
      current = {
        header: line,
        kind,
        attrs: parseTscnAttributes(line),
        props: new Map()
      };
      continue;
    }
    if (!current) continue;
    const equalsIndex = line.indexOf("=");
    if (equalsIndex < 0) continue;
    current.props.set(line.slice(0, equalsIndex).trim(), line.slice(equalsIndex + 1).trim());
  }
  if (current) blocks.push(current);
  return blocks;
}

function parseTscnAttributes(header: string): Record<string, string> {
  const attrs: Record<string, string> = {};
  for (const match of header.matchAll(/([A-Za-z_][A-Za-z0-9_]*)=(?:"([^"]*)"|([^\s\]]+))/g)) {
    attrs[match[1]] = match[2] ?? match[3] ?? "";
  }
  return attrs;
}

function tscnExtResources(blocks: TscnBlock[]): Map<string, { type: string; path: string }> {
  const resources = new Map<string, { type: string; path: string }>();
  for (const block of blocks) {
    if (block.kind !== "ext_resource") continue;
    const id = block.attrs.id;
    const resourcePath = block.attrs.path;
    if (!id || !resourcePath) continue;
    resources.set(id, { type: block.attrs.type ?? "", path: resourcePath });
  }
  return resources;
}

function tscnNodes(blocks: TscnBlock[]): TscnNode[] {
  const nodes: TscnNode[] = [];
  for (const block of blocks) {
    if (block.kind !== "node") continue;
    const name = block.attrs.name;
    if (!name) continue;
    const parent = block.attrs.parent ?? ".";
    nodes.push({
      name,
      type: block.attrs.type ?? "",
      parent,
      path: parent === "." ? name : `${parent}/${name}`,
      props: block.props
    });
  }
  return nodes;
}

function spritePriority(name: string): number {
  if (/shell|room|map|background|base|底图|背景/i.test(name)) return 2;
  return 1;
}

function collisionRectsFromTscn(blocks: TscnBlock[], nodes: TscnNode[], sceneToCanvas: Point2): PrototypeRectSpec[] {
  const rectangleShapes = new Map<string, { width: number; height: number }>();
  for (const block of blocks) {
    if (block.kind !== "sub_resource" || block.attrs.type !== "RectangleShape2D") continue;
    const size = parseVector2(block.props.get("size") ?? "");
    if (!block.attrs.id || !size) continue;
    rectangleShapes.set(block.attrs.id, { width: size.x, height: size.y });
  }

  const rects: PrototypeRectSpec[] = [];
  for (const node of nodes) {
    if (node.type !== "CollisionShape2D") continue;
    const shapeId = subResourceId(node.props.get("shape") ?? "");
    const size = shapeId ? rectangleShapes.get(shapeId) : undefined;
    if (!size) continue;
    const center = addPoints(globalNodePosition(node, nodes), sceneToCanvas);
    rects.push({
      id: sanitizeId(node.name),
      rect: {
        x: center.x - size.width / 2,
        y: center.y - size.height / 2,
        width: size.width,
        height: size.height
      }
    });
  }
  return dedupeRectSpecs(rects);
}

function markerPointsFromTscn(nodes: TscnNode[], sceneToCanvas: Point2): PrototypePointSpec[] {
  return nodes
    .filter((node) => node.type === "Marker2D")
    .map((node) => ({
      id: sanitizeId(node.name),
      name: node.name,
      position: addPoints(globalNodePosition(node, nodes), sceneToCanvas)
    }));
}

function globalNodePosition(node: TscnNode, nodes: TscnNode[], seen = new Set<string>()): Point2 {
  if (seen.has(node.path)) return { x: 0, y: 0 };
  seen.add(node.path);
  const own = parseVector2(node.props.get("position") ?? "") ?? { x: 0, y: 0 };
  if (!node.parent || node.parent === ".") return own;
  const parent = nodes.find((candidate) => candidate.path === node.parent);
  if (!parent) return own;
  return addPoints(globalNodePosition(parent, nodes, seen), own);
}

function addPoints(a: Point2, b: Point2): Point2 {
  return { x: a.x + b.x, y: a.y + b.y };
}

function extResourceId(value: string): string | undefined {
  return value.match(/ExtResource\("([^"]+)"\)/)?.[1];
}

function subResourceId(value: string): string | undefined {
  return value.match(/SubResource\("([^"]+)"\)/)?.[1];
}

function scriptPathFromScene(sceneText: string): string | undefined {
  const match = sceneText.match(/path="([^"]+\.gd)"/);
  if (!match) return undefined;
  return godotResourceToRepoRelative(match[1]);
}

async function readScriptChain(repoRoot: string, scriptPath: string, seen = new Set<string>()): Promise<ScriptText[]> {
  if (seen.has(scriptPath)) return [];
  seen.add(scriptPath);
  const text = await fs.readFile(resolveRepoPath(repoRoot, scriptPath), "utf8");
  const parentPath = extendsScriptPath(text);
  const parentScripts = parentPath ? await readScriptChain(repoRoot, parentPath, seen) : [];
  return [{ repoPath: scriptPath, text }, ...parentScripts];
}

function extendsScriptPath(scriptText: string): string | undefined {
  const match = scriptText.match(/extends\s+"([^"]+\.gd)"/);
  return match ? godotResourceToRepoRelative(match[1]) : undefined;
}

function firstStringConstant(scripts: ScriptText[], names: string[]): string | undefined {
  for (const script of scripts) {
    for (const name of names) {
      const match = script.text.match(new RegExp(`const\\s+${name}\\s*:=\\s*"([^"]+)"`));
      if (match) return match[1];
    }
  }
  return undefined;
}

function firstVectorConstant(scripts: ScriptText[], names: string[]): { x: number; y: number } | undefined {
  for (const script of scripts) {
    for (const name of names) {
      const match = script.text.match(new RegExp(`const\\s+${name}\\s*:=\\s*Vector2i?\\(([^)]+)\\)`));
      if (!match) continue;
      const values = numericArgs(match[1]);
      if (values.length >= 2) return { x: values[0], y: values[1] };
    }
  }
  return undefined;
}

async function prototypeImageLayers(repoRoot: string, info: PrototypeSceneInfo): Promise<ImageLayer[]> {
  const images: ImageLayer[] = [{
    id: "img_scene_base",
    name: "场景底图",
    asset: info.mapImagePath,
    kind: "base",
    position: info.mapImagePosition ?? { x: 0, y: 0 },
    size: info.canvas,
    zIndex: 0,
    opacity: 1,
    visible: true,
    locked: true,
    runtimeExport: false,
    sourceLayerId: "godot_scene"
  }];
  for (const [index, patch] of info.repairPatches.entries()) {
    const size = patch.size ?? await imageDimensions(resolveRepoPath(repoRoot, patch.path));
    images.push({
      id: `img_patch_${(index + 1).toString().padStart(3, "0")}`,
      name: `修补图 ${index + 1}`,
      asset: patch.path,
      kind: "foreground",
      position: patch.position,
      size,
      zIndex: index + 1,
      opacity: 1,
      visible: true,
      locked: true,
      runtimeExport: false,
      sourceLayerId: "godot_scene_patch"
    });
  }
  return images;
}

function pointObject(spec: PrototypePointSpec): PointObject {
  return {
    id: spec.id,
    name: spec.name,
    type: "event_anchor",
    position: spec.position,
    facing: "down",
    tags: ["godot_marker"]
  };
}

function rectCollision(spec: PrototypeRectSpec, index: number): CollisionLayerObject {
  const rect = spec.rect;
  return {
    id: spec.id || `collision_rect_${(index + 1).toString().padStart(3, "0")}`,
    name: spec.id || `碰撞矩形 ${index + 1}`,
    kind: "world",
    shape: {
      type: "polygon",
      points: rectPoints(rect.x, rect.y, rect.width, rect.height)
    },
    collisionLayer: 1,
    collisionMask: 0,
    debugColor: "#ef4444",
    enabled: true
  };
}

function polygonOcclusion(spec: DemoShapeSpec): OcclusionObject {
  return {
    id: spec.id,
    name: spec.id,
    shape: { type: "polygon", points: spec.points },
    baselineY: Math.max(...spec.points.map((point) => point.y)),
    sortMode: "foot_y",
    zIndex: 100,
    debugColor: "#8b5cf6",
    enabled: true
  };
}

function parseRepairPatches(scripts: ScriptText[]): PrototypeImagePatch[] {
  const patches: PrototypeImagePatch[] = [];
  for (const script of scripts) {
    const entries = script.text.matchAll(/\{\s*"path"\s*:\s*"([^"]+)"\s*,\s*"position"\s*:\s*Vector2\(([^)]+)\)([\s\S]*?)\}/g);
    for (const match of entries) {
      const repoPath = godotResourceToRepoRelative(match[1]);
      const positionValues = numericArgs(match[2]);
      if (!repoPath || positionValues.length < 2) continue;
      const sizeMatch = match[3].match(/"target_size"\s*:\s*Vector2i?\(([^)]+)\)/);
      const sizeValues = sizeMatch ? numericArgs(sizeMatch[1]) : [];
      patches.push({
        path: repoPath,
        position: { x: positionValues[0], y: positionValues[1] },
        size: sizeValues.length >= 2 ? { width: sizeValues[0], height: sizeValues[1] } : undefined
      });
    }
  }
  return patches;
}

function parseCollisionRects(scripts: ScriptText[]): PrototypeRectSpec[] {
  const rects: PrototypeRectSpec[] = [];
  for (const script of scripts) {
    const namedMatches = script.text.matchAll(/\{\s*"id"\s*:\s*"([^"]+)"\s*,\s*"rect"\s*:\s*Rect2\(([^)]+)\)/g);
    for (const match of namedMatches) {
      const values = numericArgs(match[2]);
      if (values.length >= 4) {
        rects.push({ id: sanitizeId(match[1]), rect: { x: values[0], y: values[1], width: values[2], height: values[3] } });
      }
    }
    const genericMatches = script.text.matchAll(/Rect2\(([-0-9.,\s]+)\)/g);
    let genericIndex = 1;
    for (const match of genericMatches) {
      if (script.text.slice(Math.max(0, match.index - 40), match.index).includes('"rect"')) continue;
      const values = numericArgs(match[1]);
      if (values.length >= 4) {
        rects.push({
          id: `rect_${path.basename(script.repoPath, ".gd").toLowerCase()}_${genericIndex.toString().padStart(3, "0")}`,
          rect: { x: values[0], y: values[1], width: values[2], height: values[3] }
        });
        genericIndex += 1;
      }
    }
  }
  return dedupeRectSpecs(rects);
}

function parsePrototypeOcclusionPolygons(scripts: ScriptText[]): DemoShapeSpec[] {
  const polygons: DemoShapeSpec[] = [];
  for (const script of scripts) {
    const roofMatch = script.text.match(/var\s+roof_points\s*:=\s*PackedVector2Array\(\[([\s\S]*?)\]\)/);
    if (!roofMatch) continue;
    const points = vector2Matches(roofMatch[1]);
    if (points.length >= 3) {
      polygons.push({ id: "town_hall_roof_mask", points });
    }
  }
  return polygons;
}

function dedupeRectSpecs(rects: PrototypeRectSpec[]): PrototypeRectSpec[] {
  const seen = new Set<string>();
  const result: PrototypeRectSpec[] = [];
  for (const rect of rects) {
    const key = `${rect.rect.x},${rect.rect.y},${rect.rect.width},${rect.rect.height}`;
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(rect);
  }
  return result;
}

function sanitizeId(value: string): string {
  return value.replace(/[^A-Za-z0-9_-]+/g, "_").replace(/^_+|_+$/g, "") || "item";
}

function rectPoints(x: number, y: number, width: number, height: number): Point2[] {
  return [
    { x, y },
    { x: x + width, y },
    { x: x + width, y: y + height },
    { x, y: y + height }
  ];
}

async function imageDimensions(filePath: string): Promise<{ width: number; height: number }> {
  const buffer = await fs.readFile(filePath);
  if (buffer.length >= 24 && buffer.toString("ascii", 1, 4) === "PNG") {
    return { width: buffer.readUInt32BE(16), height: buffer.readUInt32BE(20) };
  }
  const jpegSize = jpegDimensions(buffer);
  if (jpegSize) return jpegSize;
  throw new MapWorkbenchInputError(`暂不支持读取图片尺寸：${filePath}`);
}

function jpegDimensions(buffer: Buffer): { width: number; height: number } | undefined {
  if (buffer.length < 4 || buffer[0] !== 0xff || buffer[1] !== 0xd8) return undefined;
  let offset = 2;
  while (offset + 9 < buffer.length) {
    if (buffer[offset] !== 0xff) {
      offset += 1;
      continue;
    }
    const marker = buffer[offset + 1];
    const length = buffer.readUInt16BE(offset + 2);
    if (length < 2) return undefined;
    if (marker >= 0xc0 && marker <= 0xc3) {
      return {
        height: buffer.readUInt16BE(offset + 5),
        width: buffer.readUInt16BE(offset + 7)
      };
    }
    offset += 2 + length;
  }
  return undefined;
}

function escapePowerShellSingleQuoted(value: string): string {
  return value.replace(/'/g, "''");
}

function generatedPath(repoRoot: string, mapId: string, filename: string): string {
  const generatedRoot = path.resolve(repoRoot, "game/world/maps", safeMapId(mapId), "generated");
  const filePath = path.resolve(generatedRoot, filename);
  const relative = path.relative(generatedRoot, filePath);
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new MapWorkbenchInputError("生成文件路径越界");
  }
  return filePath;
}

function resolveRepoPath(repoRoot: string, value: string): string {
  const normalized = value.replace(/\\/g, "/").replace(/^\/+/, "");
  const filePath = path.resolve(repoRoot, normalized);
  const relative = path.relative(repoRoot, filePath);
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new MapWorkbenchInputError("路径越界");
  }
  return filePath;
}

export function resolveWorkbenchAssetPath(repoRoot: string, value: string): string {
  const normalized = value.replace(/\\/g, "/").replace(/^\/+/, "");
  const filePath = resolveRepoPath(repoRoot, normalized);
  const allowedRoots = [
    "game/world/maps",
    "game/world/prototypes",
    "game/assets"
  ].map((root) => path.resolve(repoRoot, root));
  if (!isPathInsideAny(filePath, allowedRoots)) {
    throw new MapWorkbenchInputError("只能读取地图工作台需要的媒体资源");
  }
  const allowedExtensions = new Set([
    ".png",
    ".jpg",
    ".jpeg",
    ".webp",
    ".gif",
    ".ogg",
    ".wav",
    ".mp3"
  ]);
  if (!allowedExtensions.has(path.extname(normalized).toLowerCase())) {
    throw new MapWorkbenchInputError("只能读取图片或音频资源");
  }
  if (!fsSync.existsSync(filePath)) {
    throw new MapWorkbenchInputError(`资源不存在：${normalized}`);
  }
  const realFilePath = fsSync.realpathSync.native(filePath);
  const realAllowedRoots = allowedRoots
    .filter((root) => fsSync.existsSync(root))
    .map((root) => fsSync.realpathSync.native(root));
  if (!isPathInsideAny(realFilePath, realAllowedRoots)) {
    throw new MapWorkbenchInputError("只能读取地图工作台需要的媒体资源");
  }
  return filePath;
}

function isPathInsideAny(filePath: string, roots: string[]): boolean {
  return roots.some((root) => {
    const relative = path.relative(root, filePath);
    return relative === "" || (!!relative && !relative.startsWith("..") && !path.isAbsolute(relative));
  });
}

function repoRelative(repoRoot: string, filePath: string): string {
  return path.relative(repoRoot, filePath).replace(/\\/g, "/");
}

function safeMapId(value: unknown): string {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]+$/.test(value)) {
    throw new MapWorkbenchInputError("mapId 只允许英文、数字、下划线和短横线");
  }
  return value;
}

function safePixelworkRoot(value: string): string {
  const normalized = value.replace(/\\/g, "/").replace(/^\/+/, "");
  if (!normalized.startsWith("game/world/maps/pixelwork_map_stitch/")) {
    throw new MapWorkbenchInputError("Pixelwork 路径必须位于 game/world/maps/pixelwork_map_stitch/");
  }
  return normalized;
}

function safeGodotScenePath(repoRoot: string, value: string): string {
  const normalized = value.replace(/\\/g, "/").replace(/^\/+/, "");
  if (!normalized.startsWith("game/world/prototypes/") || !normalized.endsWith(".tscn")) {
    throw new MapWorkbenchInputError("Godot 场景必须位于 game/world/prototypes/ 且为 .tscn");
  }
  const filePath = resolveRepoPath(repoRoot, normalized);
  if (!fsSync.existsSync(filePath)) {
    throw new MapWorkbenchInputError(`Godot 场景不存在：${normalized}`);
  }
  return normalized;
}

async function importDemoSceneRuntimeSpecs(repoRoot: string, scenePath: string, document: MapToolDocument): Promise<void> {
  const sceneText = await fs.readFile(resolveRepoPath(repoRoot, scenePath), "utf8");
  const scriptMatch = sceneText.match(/path="([^"]+\.gd)"/);
  if (!scriptMatch) return;
  const scriptPath = godotResourceToRepoRelative(scriptMatch[1]);
  if (!scriptPath) return;
  const scriptText = await fs.readFile(resolveRepoPath(repoRoot, scriptPath), "utf8");

  for (const spec of parseShapeSpecs(scriptText, "_world_block_specs")) {
    addDemoCollision(document, spec, "world", "#ef4444");
  }
  for (const spec of parseShapeSpecs(scriptText, "_water_block_specs")) {
    addDemoCollision(document, spec, "water", "#3b82f6");
  }
  for (const spec of parseShapeSpecs(scriptText, "_occluder_specs")) {
    addDemoOcclusion(document, spec);
  }
  for (const spec of parseInteractableSpecs(scriptText)) {
    addDemoInteraction(document, spec);
  }
}

interface DemoShapeSpec {
  id: string;
  points: Array<{ x: number; y: number }>;
}

interface DemoInteractableSpec {
  id: string;
  label: string;
  kind: string;
  roomId: string;
  position: { x: number; y: number };
  size: { width: number; height: number };
  description: string;
}

function addDemoCollision(document: MapToolDocument, spec: DemoShapeSpec, kind: "world" | "water", color: string): void {
  if (spec.points.length < 3 || document.layers.collision.some((item) => item.id === spec.id)) return;
  document.layers.collision.push({
    id: spec.id,
    name: spec.id,
    kind,
    shape: { type: "polygon", points: spec.points },
    collisionLayer: 1,
    collisionMask: 0,
    debugColor: color,
    enabled: true
  });
}

function addDemoOcclusion(document: MapToolDocument, spec: DemoShapeSpec): void {
  if (spec.points.length < 3 || document.layers.occlusion.some((item) => item.id === spec.id)) return;
  document.layers.occlusion.push({
    id: spec.id,
    name: spec.id,
    shape: { type: "polygon", points: spec.points },
    baselineY: Math.max(...spec.points.map((point) => point.y)),
    sortMode: "foot_y",
    zIndex: 100,
    debugColor: "#8b5cf6",
    enabled: true
  });
}

function addDemoInteraction(document: MapToolDocument, spec: DemoInteractableSpec): void {
  if (document.layers.interactions.some((item) => item.id === spec.id)) return;
  document.layers.interactions.push({
    id: spec.id,
    name: spec.label || spec.id,
    type: spec.kind === "door" ? "door" : "debug",
    targetId: spec.roomId || spec.id,
    primaryAction: spec.kind === "door" ? "enter" : "inspect",
    shape: {
      type: "rect",
      x: spec.position.x - spec.size.width / 2,
      y: spec.position.y - spec.size.height / 2,
      width: spec.size.width,
      height: spec.size.height
    },
    tags: [spec.kind || "info"],
    enabled: true
  });
  if (spec.kind === "door" && !document.layers.doors.some((item) => item.id === spec.id)) {
    document.layers.doors.push({
      id: spec.id,
      name: spec.label || spec.id,
      fromSceneId: document.mapId,
      toSceneId: spec.roomId || spec.id,
      fromPoint: { x: spec.position.x, y: spec.position.y, facing: "up" },
      toPoint: { x: 0, y: 0, facing: "down" },
      standPoint: { x: spec.position.x, y: spec.position.y + Math.max(48, spec.size.height / 2) },
      hitAreaId: spec.id,
      transitionTicks: 2,
      tags: ["door"]
    });
  }
}

function parseShapeSpecs(scriptText: string, functionName: string): DemoShapeSpec[] {
  const body = extractFunctionBody(scriptText, functionName);
  const specs: DemoShapeSpec[] = [];
  for (const entry of dictionaryEntries(body)) {
    const id = quotedField(entry, "id");
    if (!id) continue;
    const points = parsePointsExpression(fieldExpression(entry, "points"));
    if (points.length >= 3) specs.push({ id, points });
  }
  return specs;
}

function parseInteractableSpecs(scriptText: string): DemoInteractableSpec[] {
  const body = extractFunctionBody(scriptText, "_interactable_specs");
  const specs: DemoInteractableSpec[] = [];
  for (const entry of dictionaryEntries(body)) {
    const id = quotedField(entry, "id");
    const position = parseVector2(fieldExpression(entry, "position"));
    const size = parseVector2(fieldExpression(entry, "size"));
    if (!id || !position || !size) continue;
    specs.push({
      id,
      label: quotedField(entry, "label") || id,
      kind: quotedField(entry, "kind") || "info",
      roomId: quotedField(entry, "room_id") || "",
      position,
      size: { width: size.x, height: size.y },
      description: quotedField(entry, "description") || ""
    });
  }
  return specs;
}

function extractFunctionBody(scriptText: string, functionName: string): string {
  const start = scriptText.indexOf(`func ${functionName}`);
  if (start < 0) return "";
  const next = scriptText.indexOf("\nfunc ", start + 1);
  return scriptText.slice(start, next >= 0 ? next : undefined);
}

function dictionaryEntries(body: string): string[] {
  return body.split(/\r?\n/).map((line) => line.trim()).filter((line) => line.startsWith("{") && line.endsWith("},") || line.startsWith("{") && line.endsWith("}"));
}

function quotedField(entry: string, field: string): string {
  const match = entry.match(new RegExp(`"${field}"\\s*:\\s*"([^"]*)"`));
  return match ? match[1] : "";
}

function fieldExpression(entry: string, field: string): string {
  const fieldIndex = entry.indexOf(`"${field}"`);
  if (fieldIndex < 0) return "";
  const colonIndex = entry.indexOf(":", fieldIndex);
  if (colonIndex < 0) return "";
  let index = colonIndex + 1;
  while (index < entry.length && /\s/.test(entry[index])) index += 1;
  const start = index;
  let squareDepth = 0;
  let parenDepth = 0;
  let inString = false;
  for (; index < entry.length; index += 1) {
    const char = entry[index];
    const previous = index > 0 ? entry[index - 1] : "";
    if (char === "\"" && previous !== "\\") inString = !inString;
    if (inString) continue;
    if (char === "[") squareDepth += 1;
    if (char === "]") squareDepth -= 1;
    if (char === "(") parenDepth += 1;
    if (char === ")") parenDepth -= 1;
    if (char === "," && squareDepth === 0 && parenDepth === 0) break;
    if (char === "}" && squareDepth === 0 && parenDepth === 0) break;
  }
  return entry.slice(start, index).trim();
}

function parsePointsExpression(expression: string): Array<{ x: number; y: number }> {
  const rect = expression.match(/_rect_points\(([^)]+)\)/);
  if (rect) {
    const values = numericArgs(rect[1]);
    if (values.length >= 4) {
      const [left, top, right, bottom] = values;
      return [
        { x: left, y: top },
        { x: right, y: top },
        { x: right, y: bottom },
        { x: left, y: bottom }
      ];
    }
  }
  const ellipse = expression.match(/_ellipse_points\(\s*Vector2\(([^)]+)\)\s*,\s*Vector2\(([^)]+)\)\s*,\s*([0-9]+)\s*\)/);
  if (ellipse) {
    const centerValues = numericArgs(ellipse[1]);
    const radiusValues = numericArgs(ellipse[2]);
    const steps = Math.max(8, Number(ellipse[3]) || 12);
    if (centerValues.length >= 2 && radiusValues.length >= 2) {
      return ellipsePoints(centerValues[0], centerValues[1], radiusValues[0], radiusValues[1], steps);
    }
  }
  return vector2Matches(expression);
}

function parseVector2(expression: string): { x: number; y: number } | undefined {
  const match = expression.match(/Vector2\(([^)]+)\)/);
  if (!match) return undefined;
  const values = numericArgs(match[1]);
  if (values.length < 2) return undefined;
  return { x: values[0], y: values[1] };
}

function vector2Matches(expression: string): Array<{ x: number; y: number }> {
  const points: Array<{ x: number; y: number }> = [];
  const matches = expression.matchAll(/Vector2\(([^)]+)\)/g);
  for (const match of matches) {
    const values = numericArgs(match[1]);
    if (values.length >= 2) points.push({ x: values[0], y: values[1] });
  }
  return points;
}

function numericArgs(value: string): number[] {
  return value.split(",").map((item) => Number(item.trim())).filter((item) => Number.isFinite(item));
}

function ellipsePoints(cx: number, cy: number, rx: number, ry: number, steps: number): Array<{ x: number; y: number }> {
  const points: Array<{ x: number; y: number }> = [];
  for (let index = 0; index < steps; index += 1) {
    const angle = (Math.PI * 2 * index) / steps;
    points.push({
      x: Math.round((cx + Math.cos(angle) * rx) * 10) / 10,
      y: Math.round((cy + Math.sin(angle) * ry) * 10) / 10
    });
  }
  return points;
}

function assertMapToolDocument(value: unknown): asserts value is MapToolDocument {
  if (!value || typeof value !== "object") {
    throw new MapWorkbenchInputError("document 必须是对象");
  }
  const document = value as Partial<MapToolDocument>;
  safeMapId(document.mapId);
  if (!document.layers || typeof document.layers !== "object") {
    throw new MapWorkbenchInputError("document.layers 缺失");
  }
}

async function readJsonFile<T>(filePath: string): Promise<T> {
  return JSON.parse(await fs.readFile(filePath, "utf8")) as T;
}

async function writeTextAtomic(filePath: string, value: string): Promise<void> {
  const tempPath = `${filePath}.${process.pid}.${Date.now()}.tmp`;
  await fs.writeFile(tempPath, value, "utf8");
  try {
    await fs.rename(tempPath, filePath);
  } catch (error) {
    await fs.rm(tempPath, { force: true });
    throw error;
  }
}

async function readOptionalJsonFile<T>(filePath: string): Promise<T | undefined> {
  const raw = await readOptionalText(filePath);
  return raw ? JSON.parse(raw) as T : undefined;
}

async function readOptionalText(filePath: string): Promise<string | undefined> {
  try {
    return await fs.readFile(filePath, "utf8");
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") {
      return undefined;
    }
    throw error;
  }
}

function readJsonBody(req: IncomingMessage): Promise<unknown> {
  return new Promise((resolve, reject) => {
    let raw = "";
    req.setEncoding("utf8");
    req.on("data", (chunk: string) => {
      raw += chunk;
      if (raw.length > MAX_REQUEST_BYTES) {
        reject(new MapWorkbenchInputError("请求内容太大"));
        req.destroy();
      }
    });
    req.on("end", () => {
      try {
        resolve(raw ? JSON.parse(raw) : {});
      } catch {
        reject(new MapWorkbenchInputError("请求 JSON 无法解析"));
      }
    });
    req.on("error", reject);
  });
}

function hashText(value: string): string {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function sendJson(res: ServerResponse, statusCode: number, body: unknown): void {
  res.statusCode = statusCode;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.end(JSON.stringify(body));
}

function sendError(res: ServerResponse, error: unknown): void {
  if (res.headersSent) {
    res.end();
    return;
  }
  const status = error instanceof MapWorkbenchInputError ? 400 : 500;
  sendJson(res, status, {
    ok: false,
    message: error instanceof Error ? error.message : "请求失败"
  });
}

function contentTypeForPath(filePath: string): string {
  const ext = path.extname(filePath).toLowerCase();
  if (ext === ".png") return "image/png";
  if (ext === ".jpg" || ext === ".jpeg") return "image/jpeg";
  if (ext === ".webp") return "image/webp";
  if (ext === ".gif") return "image/gif";
  if (ext === ".ogg") return "audio/ogg";
  if (ext === ".wav") return "audio/wav";
  if (ext === ".mp3") return "audio/mpeg";
  return "application/octet-stream";
}
