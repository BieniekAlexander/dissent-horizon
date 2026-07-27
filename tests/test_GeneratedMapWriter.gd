extends GutTest

## Tests for the map SCENE a generated map becomes (tools/map_generation): a Map node holding
## its terrain, resources and start points, packable on its own and adopted by a Scenario as
## the `$Map` every Scenario reads. Maps are built here rather than taken from the shipped
## review set — those are content, and regenerated whenever a parameter moves.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_GeneratedMapWriter.gd \
##     -gdir=res://tests/none -gexit

const _SEED: int = 4242
## Written where a test may write, and cleaned up after.
const _TERRAIN_PATH: String = "user://test_generated_map_terrain.tres"
const _SCENE_PATH: String = "user://test_generated_map.tscn"

var _writer: GeneratedMapWriter
## The map under test, freed here rather than by autofree: a map holds instanced scenes, and
## a deferred free of one that never entered the tree leaves them counted as orphans.
var _map: Map


func before_each() -> void:
	_writer = GeneratedMapWriter.new()


func after_each() -> void:
	if is_instance_valid(_map) and _map.get_parent() == null:
		_map.free()
	_map = null
	for path: String in [_TERRAIN_PATH, _SCENE_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Placement only: the passes past it move heights around and cost seconds each, and nothing
## here asks about heights.
func _params() -> MapGenerationParams:
	var params: MapGenerationParams = _writer.default_params(2)
	params.last_pass = MapGenerationParams.Pass.RESOURCES
	params.play_size_min = 70
	params.play_size_max = 80
	return params


func _built() -> Map:
	var generated: GeneratedMap = MapGenerator.generate(_params(), _SEED)
	assert_true(generated.is_valid(), str(generated.errors))
	_map = _writer.build_map(generated, _TERRAIN_PATH)
	assert_not_null(_map)
	return _map


func test_the_map_holds_its_terrain_resources_and_start_points() -> void:
	var map: Map = _built()
	assert_not_null(map.terrain_data)
	var starts: int = 0
	var pieces: int = 0
	for child: Node in map.get_children():
		if child.is_in_group(Skirmish.START_POINT_GROUP):
			starts += 1
		elif child is Entity:
			pieces += 1
	assert_eq(starts, 2, "one start point per start, inside the map")
	assert_gt(pieces, 0, "the map's resources are its children, not the scenario's")


## The map is the reusable asset: packed alone, the scene is rooted at the Map with everything
## still under it. Read from the packed state rather than instanced — instancing a map outside
## a tree just to count its children leaves the instanced pieces behind as orphans.
func test_a_map_packs_as_a_scene_of_its_own() -> void:
	var map: Map = _built()
	var before: int = map.get_child_count()
	assert_eq(GeneratedMapWriter.pack(map, _SCENE_PATH), OK)
	var state: SceneState = (load(_SCENE_PATH) as PackedScene).get_state()
	assert_eq(state.get_node_name(0), StringName(GeneratedMapWriter.MAP_NODE_NAME),
		"a Scenario reads its map as $Map")
	var children: int = 0
	var start_points: int = 0
	for i: int in range(1, state.get_node_count()):
		if state.get_node_path(i, true) == NodePath("."):
			children += 1
		if String(state.get_node_name(i)).begins_with("StartPoint"):
			start_points += 1
	assert_eq(children, before, "every child of the map is in the scene")
	assert_eq(start_points, 2)


## Packing must leave the node it packed usable: the author keeps editing the same scene.
func test_packing_restores_the_node_to_its_scenario() -> void:
	var scenario := Node3D.new()
	scenario.name = "Scenario"
	add_child_autofree(scenario)
	var map: Map = _built()
	GeneratedMapWriter.adopt(scenario, map)
	assert_eq(map.name, StringName(GeneratedMapWriter.MAP_NODE_NAME))
	assert_eq(map.owner, scenario)
	assert_eq(GeneratedMapWriter.pack(map, _SCENE_PATH), OK)
	assert_eq(map.owner, scenario, "still the scenario's after being packed")
	for child: Node in map.get_children():
		assert_eq(child.owner, scenario, "and so is everything under it")
