import { stableMapToolDocument } from "../model/mapDocument";
import type {
  AnimationObject,
  AudioObject,
  CameraObject,
  CollisionLayerObject,
  EffectObject,
  InteractionObject,
  DoorObject,
  LightOccluderObject,
  LightingObject,
  MapToolDocument,
  NavigationGrid,
  OcclusionObject,
  PointObject,
  RuntimeMapData,
  SemanticRegionObject
} from "../model/types";

export interface RuntimeSplitFiles {
  "runtime.json": RuntimeMapData;
  "navigation.json": NavigationGrid;
  "collision.json": CollisionLayerObject[];
  "occlusion.json": OcclusionObject[];
  "interaction.json": {
    interactions: InteractionObject[];
    doors: DoorObject[];
    points: PointObject[];
  };
  "lighting.json": {
    lighting: LightingObject[];
    lightOccluders: LightOccluderObject[];
  };
  "animation.json": AnimationObject[];
  "effects.json": EffectObject[];
  "audio.json": AudioObject[];
  "camera.json": CameraObject[];
  "semantic.json": SemanticRegionObject[];
}

export function exportRuntimeMap(document: MapToolDocument): RuntimeMapData {
  const stable = stableMapToolDocument(document);
  return {
    schemaVersion: 1,
    mapId: stable.mapId,
    displayName: stable.displayName,
    canvas: stable.canvas,
    source: stable.source,
    layers: stable.layers
  };
}

export function exportSplitRuntimeFiles(document: MapToolDocument): RuntimeSplitFiles {
  const runtime = exportRuntimeMap(document);
  return {
    "runtime.json": runtime,
    "navigation.json": runtime.layers.navigation,
    "collision.json": runtime.layers.collision,
    "occlusion.json": runtime.layers.occlusion,
    "interaction.json": {
      interactions: runtime.layers.interactions,
      doors: runtime.layers.doors,
      points: runtime.layers.points
    },
    "lighting.json": {
      lighting: runtime.layers.lighting,
      lightOccluders: runtime.layers.lightOccluders
    },
    "animation.json": runtime.layers.animations,
    "effects.json": runtime.layers.effects,
    "audio.json": runtime.layers.audio,
    "camera.json": runtime.layers.camera,
    "semantic.json": runtime.layers.semanticRegions
  };
}
