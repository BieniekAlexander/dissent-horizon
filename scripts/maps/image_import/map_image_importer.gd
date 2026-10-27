@tool
class_name MapImageImporter
extends RefCounted

## Imports a palette-coded drawing as a GeneratedMap, which GeneratedMapWriter.build_map turns
## into a Map exactly as it does a generated one (map-from-image.md). The pure core of the Map
## Generator dock's image mode: no scene, no editor — layers and parameters in, a map and its
## report out.
##
## The image is a one-shot SEED: an import writes a map, and the map is primary from then on.
##
## The stages, each its own class: classification and the frame (MapImageCells), edge noise and
## heights (MapImageRelief), water (MapImageWater), structures (MapImageStructures), and the
## report (MapImageImportReport). Any error fails the whole import — nothing is half-applied.

#region Properties
## The imported map, or null when the import failed.
var map: GeneratedMap = null
## The drawing as read: when it is refused before it is fitted to the cell grid — a colour not in
## the palette — the readout is drawn from it instead, pixel for pixel.
var layers: MapImageLayers = null
var cells: MapImageCells = null
var relief: MapImageRelief = null
var water: MapImageWater = null
var structures: MapImageStructures = null
var errors: PackedStringArray = PackedStringArray()
## What the report lists without failing: waterfalls skipped, water that came out other than
## drawn, features smoothing ate, walkable ground nothing can reach.
var notes: PackedStringArray = PackedStringArray()
#endregion


## Import the drawing at `path`.
static func import_path(path: String, params: MapImageImportParams) -> MapImageImporter:
	return import_layers(MapImageLayers.load_path(path), params)


static func import_layers(layers: MapImageLayers, params: MapImageImportParams) -> MapImageImporter:
	var out := MapImageImporter.new()
	out.layers = layers
	if not layers.is_valid():
		out.errors = layers.errors
		if out.errors.is_empty():
			out.errors.append("the drawing has no terrain layer")
		return out
	out.cells = MapImageCells.classify(layers)
	if not out.cells.errors.is_empty():
		out.errors = out.cells.errors
		return out
	var generation: MapGenerationParams = params.generation
	out.structures = MapImageStructures.read(
		out.cells, generation.shelter_piece, generation.building_pool
	)
	MapImageRelief.warp_edges(out.cells, params.edge_noise_cells, params.edge_noise_seed)
	out.water = MapImageWater.plan(out.cells, params)
	out.relief = MapImageRelief.build(out.cells, params, out.water, out.structures)
	if not out.cells.errors.is_empty():
		out.errors = out.cells.errors
		return out
	var terrain := TerrainData.new()
	terrain.play_size = out.cells.play_size
	terrain.heights = out.relief.heights
	out.water.finish(out.cells, terrain, params)
	out.notes.append_array(out.water.notes)
	out.notes.append_array(MapImageImportReport.listings(out, params))
	out.map = out._assemble(terrain, params)
	return out


func is_valid() -> bool:
	return errors.is_empty() and map != null


func _assemble(a_terrain: TerrainData, a_params: MapImageImportParams) -> GeneratedMap:
	var out := GeneratedMap.new()
	out.generation_seed = a_params.edge_noise_seed
	out.play_size = cells.play_size
	out.play_cell_count = Array(cells.in_play).count(1)
	out.terrain = a_terrain
	for i: int in structures.starts.size():
		out.starts.append(MapStart.at(Vector2(structures.starts[i]) + Vector2.ONE * 0.5, i))
	for placement: Dictionary in structures.placements:
		var feature := MapFeature.new()
		feature.kind = placement.kind
		feature.placements.append(placement)
		var rect: Rect2i = MapFeature.placement_rect(placement)
		feature.center = Vector2(rect.position) + Vector2(rect.size) * 0.5
		out.features.append(feature)
	for pond: MapFeature in water.ponds:
		out.features.append(pond)
	out.waters = water.waters
	return out
