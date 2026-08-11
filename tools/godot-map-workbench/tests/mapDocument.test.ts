import { describe, expect, it } from "vitest";
import {
  cellsForBrush,
  createEmptyMapDocument,
  createNavigationGrid,
  getCellType,
  nextId,
  paintCells,
  pointToCell,
  polygonAround,
  stableMapToolDocument
} from "../src/model/mapDocument";

describe("map document helpers", () => {
  it("converts pixels to navigation cells and paints a bounded brush", () => {
    const grid = createNavigationGrid(96, 72, 24);

    expect(grid.width).toBe(4);
    expect(grid.height).toBe(3);
    expect(pointToCell({ x: 49, y: 71 }, grid)).toEqual({ x: 2, y: 2 });

    const brushCells = cellsForBrush(1, 1, 3, grid);
    const painted = paintCells(grid, brushCells, "blocked");

    expect(brushCells).toHaveLength(9);
    expect(getCellType(painted, 1, 1)).toBe("blocked");
    expect(getCellType(painted, 3, 2)).toBe("unknown");

    const erased = paintCells(painted, [{ x: 1, y: 1 }], "unknown");
    expect(getCellType(erased, 1, 1)).toBe("unknown");
    expect(erased.cells).toHaveLength(8);
  });

  it("sorts runtime objects and navigation cells stably", () => {
    const document = createEmptyMapDocument("town_test", "Town Test", 96, 72);
    document.layers.navigation.cells = [
      { x: 2, y: 1, type: "water" },
      { x: 0, y: 0, type: "walkable" },
      { x: 1, y: 0, type: "blocked" }
    ];
    document.layers.navigation.regions = [
      {
        id: "nav_b",
        name: "B",
        type: "blocked",
        shape: polygonAround({ x: 50, y: 40 }),
        debugColor: "#ef4444",
        enabled: true
      },
      {
        id: "nav_a",
        name: "A",
        type: "walkable",
        shape: polygonAround({ x: 25, y: 25 }),
        debugColor: "#22c55e",
        enabled: true
      }
    ];
    document.layers.collision.push(
      {
        id: "collision_b",
        name: "B",
        kind: "world",
        shape: polygonAround({ x: 60, y: 40 }),
        collisionLayer: 2,
        collisionMask: 0,
        debugColor: "#ef4444",
        enabled: true
      },
      {
        id: "collision_a",
        name: "A",
        kind: "world",
        shape: polygonAround({ x: 20, y: 20 }),
        collisionLayer: 2,
        collisionMask: 0,
        debugColor: "#ef4444",
        enabled: true
      }
    );

    const stable = stableMapToolDocument(document);

    expect(stable.layers.collision.map((item) => item.id)).toEqual(["collision_a", "collision_b"]);
    expect(stable.layers.navigation.cells.map((cell) => `${cell.x},${cell.y}:${cell.type}`)).toEqual([
      "0,0:walkable",
      "1,0:blocked",
      "2,1:water"
    ]);
    expect(stable.layers.navigation.regions.map((region) => region.id)).toEqual(["nav_a", "nav_b"]);
  });

  it("generates the next layer id without colliding", () => {
    const document = createEmptyMapDocument("town_test");
    document.layers.points.push({
      id: "point_001",
      name: "Spawn",
      type: "spawn_point",
      position: { x: 10, y: 20 },
      facing: "down",
      tags: []
    });

    expect(nextId(document, "points", "point")).toBe("point_002");
  });

  it("generates navigation region ids without colliding with existing regions", () => {
    const document = createEmptyMapDocument("town_test");
    document.layers.navigation.regions.push({
      id: "nav_001",
      name: "Walkable",
      type: "walkable",
      shape: polygonAround({ x: 20, y: 20 }),
      debugColor: "#22c55e",
      enabled: true
    });

    expect(nextId(document, "navigation", "nav")).toBe("nav_002");
  });
});
