import { getCellType } from "../model/mapDocument";
import type { MapToolDocument, MapToolSelection, Point2, PolygonShape, Shape } from "../model/types";

export type ValidationSeverity = "error" | "warning";

export interface ValidationIssue {
  severity: ValidationSeverity;
  message: string;
  suggestion: string;
  selection?: MapToolSelection;
}

export interface ValidationResult {
  issues: ValidationIssue[];
  canSync: boolean;
}

export function validateMapToolDocument(document: MapToolDocument): ValidationResult {
  const issues: ValidationIssue[] = [];
  const ids = new Set<string>();

  if (!document.mapId || !/^[A-Za-z0-9_-]+$/.test(document.mapId)) {
    issues.push(error("mapId 不合法", "使用英文、数字、下划线或短横线。"));
  }
  if (document.canvas.width <= 0 || document.canvas.height <= 0) {
    issues.push(error("地图尺寸无效", "检查 Pixelwork manifest 或手动设置 canvas。"));
  }
  if (document.layers.navigation.cellSize <= 0) {
    issues.push(error("navigationGrid.cellSize 必须大于 0", "设置为 16、24、32 等正数。", { layer: "navigation", id: "navigation" }));
  }

  for (const [layer, items] of Object.entries(document.layers)) {
    if (layer === "navigation") continue;
    for (const item of items as Array<{ id: string }>) {
      if (!item.id) {
        issues.push(error(`${layer} 有对象缺少 id`, "给对象分配稳定 id。"));
      } else if (ids.has(item.id)) {
        issues.push(error(`对象 id 重复：${item.id}`, "修改其中一个对象 id。", { layer: layer as never, id: item.id }));
      }
      ids.add(item.id);
    }
  }
  for (const region of document.layers.navigation.regions ?? []) {
    if (!region.id) {
      issues.push(error("navigation 有通行区域缺少 id", "给通行区域分配稳定 id。"));
    } else if (ids.has(region.id)) {
      issues.push(error(`对象 id 重复：${region.id}`, "修改其中一个对象 id。", { layer: "navigation", id: region.id }));
    }
    ids.add(region.id);
  }

  for (const image of document.layers.images) {
    if (!image.asset) {
      issues.push(error(`图像层 ${image.id} 缺少资源`, "重新导入地图包或设置 asset。", { layer: "images", id: image.id }));
    }
    if (!pointInside(document, image.position)) {
      issues.push(warning(`图像层 ${image.id} 起点越界`, "检查切片坐标。", { layer: "images", id: image.id }));
    }
  }

  for (const cell of document.layers.navigation.cells) {
    if (cell.x < 0 || cell.y < 0 || cell.x >= document.layers.navigation.width || cell.y >= document.layers.navigation.height) {
      issues.push(error(`通行格越界：${cell.x},${cell.y}`, "擦除或重新生成通行格。", { layer: "navigation", id: "navigation" }));
    }
  }
  for (const region of document.layers.navigation.regions ?? []) {
    validatePolygon(document, issues, "navigation", region.id, region.shape);
  }

  for (const collision of document.layers.collision) {
    validatePolygon(document, issues, "collision", collision.id, collision.shape);
  }
  for (const occlusion of document.layers.occlusion) {
    validatePolygon(document, issues, "occlusion", occlusion.id, occlusion.shape);
    if (!Number.isFinite(occlusion.baselineY)) {
      issues.push(error(`遮挡 ${occlusion.id} 缺少 baselineY`, "设置角色脚底排序基准线。", { layer: "occlusion", id: occlusion.id }));
    }
  }
  for (const interaction of document.layers.interactions) {
    validateShape(document, issues, "interactions", interaction.id, interaction.shape);
  }
  for (const door of document.layers.doors) {
    if (!door.toSceneId) {
      issues.push(error(`门 ${door.id} 缺少目标场景`, "设置 toSceneId。", { layer: "doors", id: door.id }));
    }
    validatePointNearWalkable(document, issues, "doors", door.id, door.fromPoint);
  }
  for (const point of document.layers.points) {
    validatePoint(document, issues, "points", point.id, point.position);
    validatePointNearWalkable(document, issues, "points", point.id, point.position);
  }
  for (const light of document.layers.lighting) {
    validatePoint(document, issues, "lighting", light.id, light.position);
    if (light.radius <= 0) {
      issues.push(error(`灯光 ${light.id} 半径无效`, "设置大于 0 的 radius。", { layer: "lighting", id: light.id }));
    }
  }
  for (const occluder of document.layers.lightOccluders) {
    validatePolygon(document, issues, "lightOccluders", occluder.id, occluder.shape);
  }
  for (const animation of document.layers.animations) {
    validatePoint(document, issues, "animations", animation.id, animation.position);
    if (animation.fps <= 0) {
      issues.push(error(`动画 ${animation.id} fps 无效`, "设置大于 0 的 fps。", { layer: "animations", id: animation.id }));
    }
  }
  for (const effect of document.layers.effects) {
    validatePoint(document, issues, "effects", effect.id, effect.position);
    validateShape(document, issues, "effects", effect.id, effect.emissionShape);
  }
  for (const audio of document.layers.audio) {
    validatePoint(document, issues, "audio", audio.id, audio.position);
    if (audio.radius <= 0 && audio.type !== "bgm") {
      issues.push(error(`声音 ${audio.id} 半径无效`, "设置大于 0 的 radius。", { layer: "audio", id: audio.id }));
    }
  }
  for (const camera of document.layers.camera) {
    validateShape(document, issues, "camera", camera.id, camera.shape);
    validatePoint(document, issues, "camera", camera.id, camera.targetPoint);
  }
  for (const semantic of document.layers.semanticRegions) {
    validateShape(document, issues, "semanticRegions", semantic.id, semantic.shape);
    if (!semantic.name || !semantic.type) {
      issues.push(error(`语义区 ${semantic.id} 缺少名称或类型`, "设置 name 和 type。", { layer: "semanticRegions", id: semantic.id }));
    }
  }

  return {
    issues,
    canSync: issues.every((issue) => issue.severity !== "error")
  };
}

function validatePolygon(
  document: MapToolDocument,
  issues: ValidationIssue[],
  layer: MapToolSelection["layer"],
  id: string,
  shape: PolygonShape
): void {
  if (!shape.points || shape.points.length < 3) {
    issues.push(error(`${id} 多边形少于 3 个点`, "补齐顶点或删除对象。", { layer, id }));
    return;
  }
  for (const point of shape.points) {
    validatePoint(document, issues, layer, id, point);
  }
}

function validateShape(
  document: MapToolDocument,
  issues: ValidationIssue[],
  layer: MapToolSelection["layer"],
  id: string,
  shape: Shape
): void {
  if (shape.type === "polygon") {
    validatePolygon(document, issues, layer, id, shape);
    return;
  }
  if (shape.type === "circle") {
    validatePoint(document, issues, layer, id, { x: shape.x, y: shape.y });
    if (shape.radius <= 0) {
      issues.push(error(`${id} 圆形半径无效`, "设置大于 0 的 radius。", { layer, id }));
    }
    return;
  }
  validatePoint(document, issues, layer, id, { x: shape.x, y: shape.y });
  validatePoint(document, issues, layer, id, { x: shape.x + shape.width, y: shape.y + shape.height });
}

function validatePoint(
  document: MapToolDocument,
  issues: ValidationIssue[],
  layer: MapToolSelection["layer"],
  id: string,
  point: Point2
): void {
  if (!pointInside(document, point)) {
    issues.push(error(`${id} 坐标越界`, "移动到地图边界内。", { layer, id }));
  }
}

function validatePointNearWalkable(
  document: MapToolDocument,
  issues: ValidationIssue[],
  layer: MapToolSelection["layer"],
  id: string,
  point: Point2
): void {
  const grid = document.layers.navigation;
  for (const region of grid.regions ?? []) {
    if (!region.enabled) continue;
    if ((region.type === "walkable" || region.type === "door" || region.type === "soft_blocked") && shapeContainsPoint(region.shape, point)) {
      return;
    }
  }
  const cellX = Math.floor(point.x / grid.cellSize);
  const cellY = Math.floor(point.y / grid.cellSize);
  for (let y = cellY - 1; y <= cellY + 1; y += 1) {
    for (let x = cellX - 1; x <= cellX + 1; x += 1) {
      const type = getCellType(grid, x, y);
      if (type === "walkable" || type === "door" || type === "soft_blocked") {
        return;
      }
    }
  }
  issues.push(warning(`${id} 不在可通行格附近`, "把点位移到 walkable/door 附近，或补通行格。", { layer, id }));
}

function shapeContainsPoint(shape: Shape, point: Point2): boolean {
  if (shape.type === "circle") {
    return Math.hypot(shape.x - point.x, shape.y - point.y) <= shape.radius;
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

function pointInside(document: MapToolDocument, point: Point2): boolean {
  return point.x >= 0 && point.y >= 0 && point.x <= document.canvas.width && point.y <= document.canvas.height;
}

function error(message: string, suggestion: string, selection?: MapToolSelection): ValidationIssue {
  return { severity: "error", message, suggestion, selection };
}

function warning(message: string, suggestion: string, selection?: MapToolSelection): ValidationIssue {
  return { severity: "warning", message, suggestion, selection };
}
