@tool
class_name TileType
extends Resource

## One entry in a TerrainTileCatalog — the definition a per-cell byte index refers to.
## A cell's byte in TerrainData.tile_types indexes into the catalog's `types` array to
## reach one of these. Properties here are shared once per type (not repeated per cell).
##
## Passability is PERMANENT and type-driven (water/forest = not passable, forever); the
## only temporary obstruction is buildings (tracked separately by TerrainGrid). Heights
## are a separate layer — a cell can be an Open (passable, buildable) type yet still be
## non-buildable because it's sloped (see TerrainGrid.is_flat) or impassable because it's
## too steep (TerrainGrid._STEEP, the distinct cliff layer).

## Human-readable name (inspector/debug only).
@export var name: String = "Open"

## Whether units may traverse a cell of this type. False = a permanent barrier
## (water, forest, cliff-type, scripted no-go). Feeds TerrainGrid's _BLOCKED bit.
@export var passable: bool = true

## Whether structures may be placed on a cell of this type. Only meaningful when
## `passable`; the final buildability of a cell also requires flat ground
## (TerrainGrid.is_flat), so a buildable type on a slope is still not buildable.
@export var buildable: bool = true

## Whether a cell of this type contributes SURFACE geometry to the visual terrain mesh.
## This is a VISUAL concern, deliberately separate from `passable` (a NAV concern): water
## and forest are impassable yet still rendered (true), while cliff / scripted no-go are
## rendered as literal holes in the mesh — the background shows through — so their surface
## is omitted (false). HeightmapMeshGenerator reads this per cell; a false value skips the
## cell's quad. (Cells that are too STEEP become holes regardless, via corner-height spread.)
@export var renders_surface: bool = true

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
