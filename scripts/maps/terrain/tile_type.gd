@tool
class_name TileType
extends Resource

## One entry in a TerrainTileCatalog — a GROUND MATERIAL, the definition a per-cell byte
## index refers to. A cell's byte in TerrainData.tile_types indexes into the catalog's `types`
## array to reach one of these. Properties here are shared once per type (not repeated per cell).
##
## A material is art only: every material is walkable and buildable. What makes ground
## impassable is always visible in its geometry — a slope too steep (TerrainGrid._STEEP), deep
## water, a void the mesh bake found, or the edge of play.
## gdd/systems/terrain-and-navigation/map-composition.md §What survives of the tile-type layer.

## Human-readable name (inspector/debug only).
@export var name: String = "Grass"

## Flat albedo the baseline terrain shader shows for a cell of this type, until real
## per-type texturing lands (see the reserved `texture` below). HeightmapMeshGenerator bakes
## this into the mesh's vertex colours, so re-painting a cell and rebuilding the mesh picks
## up edits here with no code change.
@export var map_color: Color = DEFAULT_MAP_COLOR

## Fallback albedo used for this type and for unknown/out-of-range indices (see
## TerrainTileCatalog.map_color) — a neutral open-ground green.
const DEFAULT_MAP_COLOR: Color = Color(0.22, 0.40, 0.22)

## Per-type ground texture. When set, it becomes the cell's albedo IN PLACE OF map_color
## (map_color stays the fallback for untextured types and for map-wide overlays). The
## catalog packs every type's texture into a Texture2DArray whose layer index equals the
## tile-type index, and the terrain shader samples the layer picked by the per-vertex index
## baked into COLOR.a. Leave null for a flat-colour type; all textures are normalised to a
## common size (TerrainTileCatalog.TILE_TEXTURE_SIZE) when packed.
@export var texture: Texture2D

# --- reserved for later, not built now ---
# @export var move_cost: float = 1.0
# @export var harvestable: bool = false  # e.g. a forest that converts to Open when cleared
