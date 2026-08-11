import { createEmptyMapDocument, stableMapToolDocument } from "../model/mapDocument";
import type { ImageLayer, MapToolDocument, Shape } from "../model/types";

export interface PixelworkManifest {
  version: number;
  format: string;
  resource_root: string;
  scene_file?: string;
  runtime_script?: string;
  annotations_file?: string;
  coordinate_system?: string;
  canvas: {
    width: number;
    height: number;
  };
  layers: PixelworkLayer[];
}

export interface PixelworkLayer {
  id: string;
  label: string;
  folder: string;
  visible: boolean;
  order: number;
  tiles: PixelworkTile[];
}

export interface PixelworkTile {
  key: string;
  name: string;
  layer: string;
  layer_label: string;
  image: string;
  mime_type: string;
  guid: string;
  pixel: {
    x: number;
    y: number;
    width: number;
    height: number;
  };
}

export interface PixelworkAnnotations {
  version: number;
  coordinate_system?: string;
  layers?: Array<{
    id: string;
    label: string;
    order?: number;
    color?: string;
    shapes?: Array<{
      id?: string;
      type?: string;
      points?: Array<{ x: number; y: number }>;
      polygon?: Array<{ x: number; y: number }>;
      rect?: { x: number; y: number; width?: number; height?: number; w?: number; h?: number };
    }>;
  }>;
}

export interface ImportPixelworkOptions {
  mapId: string;
  displayName?: string;
  manifest: PixelworkManifest;
  annotations?: PixelworkAnnotations;
  packageRoot: string;
  demoScenePath?: string;
}

type PixelworkAnnotationShape = NonNullable<NonNullable<PixelworkAnnotations["layers"]>[number]["shapes"]>[number];

export function importPixelworkPackage(options: ImportPixelworkOptions): MapToolDocument {
  const document = createEmptyMapDocument(
    options.mapId,
    options.displayName ?? options.mapId,
    options.manifest.canvas.width,
    options.manifest.canvas.height
  );
  document.source = {
    kind: "pixelwork_map_stitch",
    root: options.demoScenePath ?? options.packageRoot,
    packageRoot: options.packageRoot,
    demoScene: options.demoScenePath,
    godotManifest: `${options.packageRoot}/${basenameFromManifest(options.manifest)}`,
    annotations: options.manifest.annotations_file ? `${options.packageRoot}/${options.manifest.annotations_file}` : undefined
  };
  document.layers.images = importImageLayers(options.manifest, options.packageRoot);
  importAnnotationShapes(document, options.annotations);
  return stableMapToolDocument(document);
}

function basenameFromManifest(manifest: PixelworkManifest): string {
  const scene = manifest.scene_file ?? "pixelwork_map.tscn";
  return scene.replace(/\.tscn$/i, "_godot.json");
}

function importImageLayers(manifest: PixelworkManifest, packageRoot: string): ImageLayer[] {
  const layers: ImageLayer[] = [];
  for (const layer of manifest.layers) {
    const kind = imageKindForLayer(layer.id);
    for (const tile of layer.tiles) {
      layers.push({
        id: `img_${layer.id}_${sanitizeId(tile.key || tile.name)}`,
        name: `${layer.label} ${tile.name}`,
        asset: `${packageRoot}/${tile.image}`.replace(/\\/g, "/"),
        kind,
        position: { x: tile.pixel.x, y: tile.pixel.y },
        size: { width: tile.pixel.width, height: tile.pixel.height },
        zIndex: layer.order,
        opacity: kind === "reference" ? 0.45 : 1,
        visible: layer.visible,
        locked: true,
        runtimeExport: kind !== "reference",
        sourceLayerId: layer.id,
        tileKey: tile.key
      });
    }
  }
  return layers;
}

function importAnnotationShapes(document: MapToolDocument, annotations: PixelworkAnnotations | undefined): void {
  if (!annotations?.layers) {
    return;
  }
  for (const layer of annotations.layers) {
    for (const [index, rawShape] of (layer.shapes ?? []).entries()) {
      const shape = annotationShape(rawShape);
      if (!shape || shape.type !== "polygon") {
        continue;
      }
      const id = rawShape.id ?? `${layer.id}_${(index + 1).toString().padStart(3, "0")}`;
      if (layer.id === "collision") {
        document.layers.collision.push({
          id,
          name: id,
          kind: "world",
          shape,
          collisionLayer: 1,
          collisionMask: 0,
          debugColor: layer.color ?? "#ef4444",
          enabled: true
        });
      } else if (layer.id === "occlusion" || layer.id === "top") {
        document.layers.occlusion.push({
          id,
          name: id,
          shape,
          baselineY: Math.max(...shape.points.map((point) => point.y)),
          sortMode: "foot_y",
          zIndex: layer.order ?? 100,
          debugColor: layer.color ?? "#8b5cf6",
          enabled: true
        });
      } else if (layer.id === "adjust") {
        document.layers.interactions.push({
          id,
          name: id,
          type: "debug",
          targetId: "",
          primaryAction: "inspect",
          shape,
          tags: ["adjust"],
          enabled: true
        });
      }
    }
  }
}

function annotationShape(rawShape: PixelworkAnnotationShape): Shape | undefined {
  if (rawShape.points && rawShape.points.length >= 3) {
    return { type: "polygon", points: rawShape.points };
  }
  if (rawShape.polygon && rawShape.polygon.length >= 3) {
    return { type: "polygon", points: rawShape.polygon };
  }
  if (rawShape.rect) {
    const width = rawShape.rect.width ?? rawShape.rect.w ?? 0;
    const height = rawShape.rect.height ?? rawShape.rect.h ?? 0;
    if (width > 0 && height > 0) {
      return {
        type: "polygon",
        points: [
          { x: rawShape.rect.x, y: rawShape.rect.y },
          { x: rawShape.rect.x + width, y: rawShape.rect.y },
          { x: rawShape.rect.x + width, y: rawShape.rect.y + height },
          { x: rawShape.rect.x, y: rawShape.rect.y + height }
        ]
      };
    }
  }
  return undefined;
}

function imageKindForLayer(layerId: string): ImageLayer["kind"] {
  if (layerId === "surface") return "surface";
  if (layerId === "object") return "object";
  if (layerId === "foreground" || layerId === "top") return "foreground";
  if (layerId === "overall" || layerId === "base") return "base";
  return "reference";
}

function sanitizeId(value: string): string {
  return value.replace(/[^A-Za-z0-9_-]+/g, "_").replace(/^_+|_+$/g, "") || "tile";
}
