---
title: Terrain and Navigation
type: system-index
---

# Terrain and Navigation

The ground, and how things move over it.

| Note | Covers |
|---|---|
| [map-and-terrain-grid.md](map-and-terrain-grid.md) | `Map`, coordinate helpers, `TerrainGrid` passability |
| [navigation-and-pathing.md](navigation-and-pathing.md) | navmesh construction, A* budget, path straightening, RVO avoidance |
| [terrain-authoring.md](terrain-authoring.md) | the `terrain_brush` plugin, the brushable surface, idempotent editor setters |
| [mesh-baked-terrain.md](mesh-baked-terrain.md) | baking a modelled mesh into the heightfield, and `TerrainSurface` rendering |
| [tile-types.md](tile-types.md) | the `TerrainData` tile-type model and its migration |
| [water-bodies.md](water-bodies.md) | bodies of water: basins, wade depth, lithium ponds, the water surface, the Water brush |
| [map-composition.md](map-composition.md) | the map features, occupancy vs obstruction, and ground materials |
| [map-generation.md](map-generation.md) | the procedural pipeline, its topological pass and its parameter bounds |
| [map-generation-review.md](map-generation-review.md) | **review list** (2026-10-02) — the generator's speed, pass structure and parameterisation; what was built, and the proposals awaiting a decision |
| [visual-facets.md](visual-facets.md) | pass 7: the derived cosmetic layer — ground paint, trails, doodads, dressing sites — and the shortlist of what to dress |
| [agent-size-classes.md](agent-size-classes.md) | per-size navmesh erosion and clearance |
| [structure-footprints.md](structure-footprints.md) | multi-cell structures on the grid |
| [terrain-representation-rationale.md](terrain-representation-rationale.md) | why 3D, why a heightfield, why plateaus work the way they do |
| [incremental-navmesh.md](incremental-navmesh.md) | rebuilding only the navmesh a change touches — staggered chunk grids on one map, why the stagger is load-bearing, and the before/after |

**Belongs here:** anything about the shape of the world, cell passability, navmesh baking,
pathfinding, steering and avoidance, terrain authoring tools, and how terrain is drawn.

**Does not belong here:** how a unit is *ordered* to move ([commands](../commands/)) and the
flight regime of aircraft ([combat/aerial-operations](../combat/aerial-operations/)) — those
consume navigation rather than defining it.
