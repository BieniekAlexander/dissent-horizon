@tool
class_name GeneratedMapWriter
extends RefCounted

## Turns a GeneratedMap into a MAP — a Map node holding its terrain, resources, water and start
## points, saveable as a scene of its own and played by any Scenario that holds it as `$Map` —
## and describes it as a balance report.
##
## The SHELL around MapGenerator: it reads piece stats and footprints from the piece scenes,
## hands the generator plain parameters, and turns the result into nodes. Shared by the batch
## review tool (generate_maps.tscn) and the editor dock (addons/map_generator).
##
## @tool because the dock runs it inside the editor, where a non-tool script's instances and
## static initialisers do not run.

#region Constants
const SITE_SCENE: String = "res://scenes/entities/structures/nt/nt_extractionSite.tscn"
const SHELTER_SCENE: String = "res://scenes/entities/structures/nt/nt_shelter.tscn"
const EXTRACTOR_SCENE: String = "res://scenes/entities/structures/nt/nt_extractor.tscn"
## The draw weight of every neutral building in the pool. The pool itself is the whole
## neutral-building family (PieceFamilies), so a new `nt_building_*` piece joins it by being
## authored; weights are uniform because no design reason to favour a shape exists yet
## (map-generation.md §Buildings).
const BUILDING_WEIGHT: float = 1.0
const TILE_CATALOG: String = "res://resources/terrain/tile_catalog.tres"
## Every Scenario reads its map as `$Map`, so a map scene's root carries that name.
const MAP_NODE_NAME: String = "Map"
const TERRAIN_SHADER: String = "res://scenes/scenarios/s1.gdshader"
const TERRAIN_SUFFIX: String = "_terrain.tres"
const START_POINT_SCENE: String = "res://scenes/scenarios/start_point.tscn"
## How a placed piece is instanced. With edit state, packing the map stores only what the
## placement CHANGED; without it, every group the piece's own scene declares is copied onto the
## instance — derived groups included, which then outlive any change to the piece
## (tests/test_DerivedGroupsStayOnPieces).
const PLACED: PackedScene.GenEditState = PackedScene.GEN_EDIT_STATE_INSTANCE
## A start column's colour: a random hue, vivid enough to find at a glance.
const START_COLOR_SATURATION: float = 0.8
const START_COLOR_VALUE: float = 0.95
#endregion

#region Properties
## Piece id -> PackedScene, for every piece the generator may name. Filled by
## apply_piece_facts, which must run before write.
var _scenes: Dictionary = {}
#endregion


#region Parameters
## Defaults for `start_count` starts, with every piece fact read from the piece scenes.
func default_params(a_start_count: int) -> MapGenerationParams:
	var params: MapGenerationParams = MapGenerationParams.for_start_count(a_start_count)
	apply_piece_facts(params)
	return params


## Overwrite the parameters that are facts about pieces — footprints, garrison capacities, the
## building pool, the extractor's income — from the piece scenes, so none is typed by hand.
func apply_piece_facts(a_params: MapGenerationParams) -> void:
	a_params.site_piece = _piece_from(SITE_SCENE, 1.0)
	a_params.shelter_piece = _piece_from(SHELTER_SCENE, 1.0)
	a_params.building_pool = []
	for template: PieceFamilies.Template in PieceFamilies.templates_of(
		PieceFamilies.NEUTRAL_BUILDING
	):
		a_params.building_pool.append(_piece_from(template.scene_path, BUILDING_WEIGHT))
	var extractor: Node = (load(EXTRACTOR_SCENE) as PackedScene).instantiate()
	var rate: int = (extractor.get_node("EnergyExtractor") as EnergyExtractor).energy_rate
	extractor.free()
	a_params.site_energy_per_second = rate / EnergyExtractor.CYCLE_SECONDS
	a_params.pond_rate_multiplier = WaterBody.POND_RATE_MULTIPLIER


func _piece_from(a_path: String, a_weight: float) -> MapPiece:
	var scene := load(a_path) as PackedScene
	var entity := scene.instantiate() as Entity
	var footprint: Vector2i = (entity.get_node("Structure") as Structure).dimensions
	var garrison := entity.get_node_or_null("Garrison") as Garrison
	var capacity: int = garrison.capacity if garrison != null else 0
	var piece := MapPiece.of(entity.id, footprint, a_weight, capacity)
	entity.free()
	_scenes[piece.id] = scene
	return piece


#endregion


#region Scene
## Build the generated map as a MAP NODE — terrain, water, resources and start points all
## inside it — ready to add to a Scenario or pack as a scene of its own. Everything a map IS
## lives under this node; lighting, triggers and player slots belong to the Scenario around it
## (Alex, 2026-09-20).
##
## The terrain resource is saved to `a_terrain_path` first, because a scene must reference it
## by path rather than carry a copy.
func build_map(a_map: GeneratedMap, a_terrain_path: String) -> Map:
	var terrain: TerrainData = a_map.terrain
	terrain.catalog = load(TILE_CATALOG) as TerrainTileCatalog
	if ResourceSaver.save(terrain, a_terrain_path) != OK:
		return null
	# Taking the path over, rather than loading the file back, matters in the editor: a load
	# would hand back the CACHED resource from the previous write to the same path.
	terrain.take_over_path(a_terrain_path)

	var map: Map = _build_map(terrain)
	var rng := RandomNumberGenerator.new()
	rng.seed = a_map.generation_seed
	var grid_half := Vector2(terrain.grid_width(), terrain.grid_depth()) * 0.5
	for i: int in a_map.starts.size():
		var marker: Node3D = (load(START_POINT_SCENE) as PackedScene).instantiate(PLACED)
		marker.name = "StartPoint%d" % (i + 1)
		var start: Vector2 = a_map.starts[i].position
		marker.position = _world(start, grid_half, _height_under(terrain, start))
		marker.set("color", Color.from_hsv(rng.randf(), START_COLOR_SATURATION, START_COLOR_VALUE))
		_add(map, marker, map)

	var counts: Dictionary = {}
	for feature: MapFeature in a_map.features:
		if feature.kind == MapFeature.Kind.POND:
			_add(map, _pond(feature, rng, counts), map)
			continue
		for placement: Dictionary in feature.placements:
			var piece: MapPiece = placement.piece
			var entity: Node3D = (_scenes[piece.id] as PackedScene).instantiate(PLACED)
			counts[piece.id] = counts.get(piece.id, 0) + 1
			entity.name = "%s%d" % [String(piece.id), counts[piece.id]]
			var center: Vector2 = Vector2(placement.origin) + Vector2(piece.footprint) * 0.5
			entity.position = _world(center, grid_half, _height_under(terrain, center))
			_add(map, entity, map)

	for water: Dictionary in a_map.chasm_waters:
		_add(map, _chasm_water(water, counts), map)
	return map


## Write `a_map` as a map SCENE at `a_scene_path`, with its terrain beside it. Overwrites both.
## The scene's root is the Map, named "Map" so that instancing it under a Scenario satisfies
## the `$Map` every Scenario looks for.
func write(a_map: GeneratedMap, a_scene_path: String) -> Error:
	var map: Map = build_map(a_map, a_scene_path.get_basename() + TERRAIN_SUFFIX)
	if map == null:
		return ERR_CANT_CREATE
	return pack(map, a_scene_path)


## Pack an existing map node as a scene. Used on the node in the open Scenario, so a map the
## author has adjusted by hand is saved as they left it.
static func pack(a_map: Map, a_scene_path: String) -> Error:
	var held_owner: Node = a_map.owner
	var held_name: String = a_map.name
	a_map.owner = null
	a_map.name = MAP_NODE_NAME
	_own_subtree(a_map, a_map)
	var packed := PackedScene.new()
	var error: Error = packed.pack(a_map)
	if error == OK:
		error = ResourceSaver.save(packed, a_scene_path)
	a_map.owner = held_owner
	a_map.name = held_name
	if held_owner != null:
		_own_subtree(a_map, held_owner)
	return error


## Give every descendant of `a_node` the same owner, which is what decides whether a node is
## saved with a scene: the Map owns its own when packed alone, the Scenario owns it in a scene.
static func _own_subtree(a_node: Node, a_owner: Node) -> void:
	for child: Node in a_node.get_children():
		# An instanced scene keeps its own internals; only its root is owned here.
		child.owner = a_owner
		if child.scene_file_path.is_empty():
			_own_subtree(child, a_owner)


## Hand a map node to a Scenario: named "Map", owned by the scene so it saves with it.
static func adopt(a_scenario: Node, a_map: Map) -> void:
	a_map.name = MAP_NODE_NAME
	a_scenario.add_child(a_map)
	a_map.owner = a_scenario
	_own_subtree(a_map, a_scenario)


func _build_map(a_terrain: TerrainData) -> Map:
	var map := Map.new()
	map.name = MAP_NODE_NAME
	map.terrain_data = a_terrain
	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion"
	region.navigation_mesh = NavigationMesh.new()
	region.add_to_group("navigation_mesh_source_group", true)
	_add(map, region, map)
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = CollisionLayers.Mask.TERRAIN
	body.collision_mask = 0
	_add(region, body, map)
	var shape_resource: HeightMapShape3D = a_terrain.to_height_shape()
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	shape.shape = shape_resource
	_add(body, shape, map)
	var mesh_generator := HeightmapMeshGenerator.new()
	mesh_generator.name = "HeightmapMeshGenerator"
	mesh_generator.shape = shape_resource
	var material := ShaderMaterial.new()
	material.shader = load(TERRAIN_SHADER) as Shader
	mesh_generator.material = material
	_add(body, mesh_generator, map)
	return map


## Properties are set BEFORE the body joins the Map: a WaterBody with a parent Map re-floods
## on every setter, and this Map is not in a tree.
func _pond(a_feature: MapFeature, a_rng: RandomNumberGenerator, a_counts: Dictionary) -> WaterBody:
	var body := WaterBody.new()
	a_counts[&"pond"] = a_counts.get(&"pond", 0) + 1
	body.name = "Pond%d" % a_counts[&"pond"]
	body.seed_cell = a_feature.pond_seed_cell
	body.level = a_feature.pond_level
	body.energy = a_feature.pond_charge
	body.charge_color = WaterBody.CHARGE_COLORS[a_rng.randi() % WaterBody.CHARGE_COLORS.size()]
	return body


## Uncharged water standing in a flooded chasm. Properties set before it joins the Map, as for
## a pond.
func _chasm_water(a_water: Dictionary, a_counts: Dictionary) -> WaterBody:
	var body := WaterBody.new()
	a_counts[&"chasm"] = a_counts.get(&"chasm", 0) + 1
	body.name = "Chasm%d" % a_counts[&"chasm"]
	body.seed_cell = a_water.seed_cell
	body.level = a_water.level
	return body


func _add(a_parent: Node, a_child: Node, a_owner: Node) -> void:
	a_parent.add_child(a_child)
	a_child.owner = a_owner


## The ground height under a cell-space point: pass 6 puts ground on several levels.
static func _height_under(terrain: TerrainData, point: Vector2) -> float:
	return terrain.cell_mean_height(Vector2i(point.floor()))


## Cell space to Map-local world: the Map sits at the origin and its grid is centred on it.
static func _world(point: Vector2, grid_half: Vector2, height: float) -> Vector3:
	return Vector3(point.x - grid_half.x, height, point.y - grid_half.y)


#endregion


#region Report
## A markdown balance report: per-currency access, cluster sizes, and every feature's favor.
## Lists the errors instead when the map failed an invariant.
static func report(map: GeneratedMap, title: String) -> PackedStringArray:
	var lines := PackedStringArray(
		[
			(
				"## %s — seed %d, play %s, passes run %d"
				% [title, map.generation_seed, map.play_size, map.passes_run]
			),
			""
		]
	)
	if map.decoration != null:
		lines.append("Decoration (pass 7, cosmetic): %s" % map.decoration.summary())
		lines.append("")
	if map.topology != null:
		var flooded: int = map.topology.flooded.count(true)
		lines.append(
			(
				(
					"%d of %d graph edges cut (%d flooded, %d ridges), %d carved open, "
					+ "%d barrier cells"
				)
				% [
					map.topology.cuts.size(),
					map.topology.graph.edges.size(),
					flooded,
					map.topology.cuts.size() - flooded,
					map.topology.carved.count(true),
					map.topology.barrier_of.size()
				]
			)
		)
		var lakes: int = 0
		var mountains: int = 0
		for cut: int in map.topology.cuts.size():
			if map.topology.grown[cut]:
				lakes += 1 if map.topology.flooded[cut] else 0
				mountains += 0 if map.topology.flooded[cut] else 1
		lines.append(
			(
				"%d cuts grown into regions: %d mountains, %d lakes"
				% [lakes + mountains, mountains, lakes]
			)
		)
	if map.traversable_fraction >= 0.0:
		var obstructed := PackedStringArray()
		for value: float in map.obstructed:
			obstructed.append("%.0f" % value)
		lines.append(
			(
				(
					"%.1f%% of the play area traversable, %.1f%% buildable; impassable cells "
					% [100.0 * map.traversable_fraction, 100.0 * map.buildable_fraction]
				)
				+ "per alliance %s" % ", ".join(obstructed)
			)
		)
	if map.elevation != null:
		var terraces: Dictionary = {}
		var tiers: Dictionary = {}
		for node: int in map.elevation.level_of_node.size():
			terraces[map.elevation.level_of_node[node]] = true
			tiers[map.elevation.tier_of_node[node]] = true
		var terrace_keys: Array = terraces.keys()
		terrace_keys.sort()
		var tier_keys: Array = tiers.keys()
		tier_keys.sort()
		lines.append(
			(
				(
					"starts on tier %d terrace %d; tiers used %s, terraces %s; "
					+ "%d ramps, %d cliff cells"
				)
				% [
					map.elevation.tier_of_node[0],
					map.elevation.level_of_node[0],
					tier_keys,
					terrace_keys,
					map.elevation.ramp_count,
					map.elevation.cliff_cells.size()
				]
			)
		)
	if map.topology != null:
		lines.append("")
	if not map.is_valid():
		for error: String in map.errors:
			lines.append("- FAILED: %s" % error)
		return lines
	var energy: PackedFloat32Array = map.accessible_value[MapFeature.Currency.SITE_ENERGY]
	var alliances: int = energy.size()
	var header: String = "| currency |"
	var rule: String = "|---|"
	for a: int in alliances:
		header += " alliance %d |" % a
		rule += "---|"
	lines.append(header + " target each | worst deviation |")
	lines.append(rule + "---|---|")
	for currency: int in MapFeature.Currency.values():
		var accessible: PackedFloat32Array = map.accessible_value[currency]
		var target: float = map.target_value[currency]
		var row: String = "| %s |" % MapFeature.Currency.keys()[currency]
		for value: float in accessible:
			row += " %.1f |" % value
		lines.append(
			(
				row
				+ (
					" %.1f | %.1f%% |"
					% [target, MapFavor.worst_deviation(accessible, target) * 100.0]
				)
			)
		)
	var sizes: Array[int] = []
	for cluster: MapFeature in map.features_of(MapFeature.Kind.BUILDING_CLUSTER):
		sizes.append(cluster.placements.size())
	sizes.sort()
	sizes.reverse()
	var building_count: int = sizes.reduce(func(total: int, n: int) -> int: return total + n, 0)
	lines.append("")
	lines.append("%d buildings in %d clusters, sizes %s" % [building_count, sizes.size(), sizes])
	lines.append_array(
		PackedStringArray(
			[
				"",
				"| feature | value | target favor | realised favor | detail |",
				"|---|---|---|---|---|"
			]
		)
	)
	for feature: MapFeature in map.features:
		var detail: String = ""
		if feature.kind == MapFeature.Kind.POND:
			detail = (
				"%d cells x %d = %d charge"
				% [feature.pond_cells.size(), feature.pond_richness, feature.pond_charge]
			)
		elif feature.kind == MapFeature.Kind.BUILDING_CLUSTER:
			detail = "%d buildings" % feature.placements.size()
		elif feature.kind == MapFeature.Kind.SITE_CLUSTER:
			detail = "%d sites" % feature.placements.size()
		lines.append(
			(
				"| %s | %.0f | %+.2f | %+.2f | %s |"
				% [
					MapFeature.Kind.keys()[feature.kind],
					feature.value,
					feature.target_favor(),
					feature.realised_favor(),
					detail
				]
			)
		)
	return lines
#endregion
