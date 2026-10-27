@tool
class_name MapImageImportParams
extends RefCounted

## The map image importer's knobs: the four the dock offers, and the generator parameters an
## imported map shares with a generated one, so the two have the same chasms and pond prices
## (map-from-image.md §Terrain).

#region Constants
## Dock-field descriptions, by property name.
const DESCRIPTIONS: Dictionary = {
	"level_step":
	"Height between adjacent levels. Smoothing grades a step into a ramp; unsmoothed, it is a cliff.",
	"smoothing_radius":
	"Box-blur radius over the heights, in corners. Features narrower than about two radii are eaten.",
	"edge_noise_cells":
	"How far region edges are pushed about, in cells, so they do not read as ruled lines. 0 is off.",
	"edge_noise_seed": "The edge noise's seed.",
}
#endregion

#region Properties
## Height between adjacent terrain levels: the blur grades a step into a ramp.
var level_step: float = MapGenerationParams.LEVEL_STEP
## Box-blur radius over the corner heights, in corners. 0 leaves every level a flat terrace with
## a step at its edge. Features narrower than about two radii are eaten, and reported.
var smoothing_radius: int = 2
## How far region edges are displaced, in cells, so terrain does not read as ruled polygons. 0
## keeps every edge exactly where it was drawn.
var edge_noise_cells: float = 1.0
## The edge noise's seed: the same drawing, parameters and seed always import the same map.
var edge_noise_seed: int = 0
## The generator's parameters for what the two share: ground height, chasm depth, and pond
## richness and charge cap. Its piece facts — the shelter and the neutral building pool — are
## what structures are matched against, so GeneratedMapWriter.apply_piece_facts must have been
## run on it.
var generation: MapGenerationParams = MapGenerationParams.new()
#endregion


## The height of terrain level `level` (1–6): the generator's ground, then one step a level.
func level_height(level: int) -> float:
	return generation.ground_height + (level - 1) * level_step
