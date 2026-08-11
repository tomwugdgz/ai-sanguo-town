import {
  DEFAULT_PIXELWORK_ENDPOINT,
  IMPORT_PIXELWORK_ENDPOINT,
  LIST_PIXELWORK_ENDPOINT,
  LOAD_MAP_ENDPOINT,
  PICK_MAP_SOURCE_FOLDER_ENDPOINT,
  SAVE_MAP_ENDPOINT
} from "./endpoints";
import type { MapToolDocument } from "../model/types";

export interface LoadMapResponse {
  ok: true;
  exists: boolean;
  document?: MapToolDocument;
  hash: string;
  mapPath?: string;
}

export interface ImportPixelworkResponse {
  ok: true;
  document: MapToolDocument;
  packageRoot?: string;
  sourceKind: "godot_scene" | "demo_scene" | "pixelwork_package";
  sourcePath: string;
  scenePath?: string;
}

export interface SaveMapResponse {
  ok: true;
  hash: string;
  paths: Record<string, string>;
  document: MapToolDocument;
}

export interface DefaultPixelworkResponse {
  ok: true;
  packageRoot: string;
  manifestPath: string;
}

export interface PixelworkPackageSummary {
  sourceKind: "editable_map" | "godot_scene" | "demo_scene" | "pixelwork_package";
  sourceLabel: string;
  packageRoot?: string;
  manifestPath?: string;
  scenePath?: string;
  mapId?: string;
  mapPath?: string;
  name: string;
  canvas: {
    width: number;
    height: number;
  };
  layers: Array<{
    id: string;
    label: string;
    tiles: number;
  }>;
  modifiedAt: string;
}

export interface ListPixelworkPackagesResponse {
  ok: true;
  packages: PixelworkPackageSummary[];
  defaultPackageRoot: string;
}

export interface PickMapSourceFolderResponse {
  ok: true;
  cancelled: boolean;
  source?: PixelworkPackageSummary;
}

export async function getDefaultPixelworkPackage(): Promise<DefaultPixelworkResponse> {
  return readJson(await fetch(DEFAULT_PIXELWORK_ENDPOINT));
}

export async function listPixelworkPackages(): Promise<ListPixelworkPackagesResponse> {
  return readJson(await fetch(LIST_PIXELWORK_ENDPOINT));
}

export async function pickMapSourceFolder(): Promise<PickMapSourceFolderResponse> {
  return readJson(await fetch(PICK_MAP_SOURCE_FOLDER_ENDPOINT, { method: "POST" }));
}

export async function importPixelworkPackage(options: {
  mapId: string;
  sourcePath?: string;
  packageRoot?: string;
  sourceKind?: "godot_scene" | "demo_scene" | "pixelwork_package";
  scenePath?: string;
}): Promise<ImportPixelworkResponse> {
  return readJson(await fetch(IMPORT_PIXELWORK_ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(options)
  }));
}

export async function loadMapToolDocument(mapId: string): Promise<LoadMapResponse> {
  const url = `${LOAD_MAP_ENDPOINT}?mapId=${encodeURIComponent(mapId)}`;
  return readJson(await fetch(url));
}

export async function saveMapToolDocument(options: {
  document: MapToolDocument;
  expectedHash: string;
  force?: boolean;
}): Promise<SaveMapResponse> {
  return readJson(await fetch(SAVE_MAP_ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(options)
  }));
}

async function readJson<T>(response: Response): Promise<T> {
  const text = await response.text();
  if (!response.ok) {
    let message = text;
    try {
      const parsed = JSON.parse(text) as { message?: string };
      message = parsed.message ?? text;
    } catch {
      // keep raw text
    }
    throw new Error(message || `请求失败：${response.status}`);
  }
  return JSON.parse(text) as T;
}
