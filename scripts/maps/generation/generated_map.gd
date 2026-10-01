@tool
class_name GeneratedMap
extends RefCounted

## What MapGenerator produces: the terrain, the starts, and the placed features — plus the
## balance report that says how fair it came out. `errors` non-empty means the generation
## FAILED an invariant and the map must not be used (map-generation.md §The pipeline).

#region Properties
var generation_seed: int = 0
## The play rectangle drawn for this map, in diamonds.
var play_size: Vector2i = Vector2i.ZERO
## Cells inside the play rectangle.
var play_cell_count: int = 0
var terrain: TerrainData = null
var starts: Array[MapStart] = []
var features: Array[MapFeature] = []

## Currency -> PackedFloat32Array of accessible value per alliance.
var accessible_value: Dictionary = {}
## Currency -> the value each alliance was meant to reach.
var target_value: Dictionary = {}

## Pass 4's decisions — cuts, barrier cells, carves — or null when generation stopped earlier.
var topology: MapTopology = null
## Pass 6's levels, cliffs and ramps, or null when generation stopped earlier.
var elevation: MapElevation = null
## The water standing in flooded chasms: one {seed_cell: Vector2i, level: float} per connected
## stretch, written as uncharged WaterBodies.
var chasm_waters: Array[Dictionary] = []
## Shares of the play area a unit can cross, and can build on — measured on the finished
## terrain (map-generation.md §Obstacle regions); -1 before pass 5 has shaped it.
var traversable_fraction: float = -1.0
var buildable_fraction: float = -1.0
## Impassable cells per alliance, each split by MapFavor.access_share: the cost each carries.
var obstructed := PackedFloat32Array()
## The last pass that ran (MapGenerationParams.last_pass, or earlier if one failed).
var passes_run: int = 0

var errors: PackedStringArray = PackedStringArray()
#endregion


func is_valid() -> bool:
	return errors.is_empty() and terrain != null


func features_of(a_kind: MapFeature.Kind) -> Array[MapFeature]:
	var matching: Array[MapFeature] = []
	matching.assign(features.filter(func(f: MapFeature) -> bool: return f.kind == a_kind))
	return matching
