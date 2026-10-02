extends GutTest

## NavManager cuts every mesh into CHUNK_SIZE_CELLS chunks, one region each, and offsets each
## mesh's chunk grid from the others'. With the grids aligned, the base mesh and every class
## mesh put their border edges on the same merge keys and Godot drops links, so paths across a
## border silently fail — see gdd/systems/terrain-and-navigation/incremental-navmesh.md
## §Why the grids are staggered. These tests drive a real NavManager on a flat fixture map
## several chunks wide.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_NavChunks.gd

const W: int = 3 * NavManager.CHUNK_SIZE_CELLS + 1  # corners; one fewer cells per side
const MAX_READY_FRAMES: int = 120
const SYNC_FRAMES: int = 10
## A straight path over flat open ground may bend by the funnel's rounding and no more.
const MAX_PATH_EXCESS: float = 1.02
const ROW: int = W / 2

var _grid: TerrainGrid
var _nav: NavManager


func before_each() -> void:
	var shape := HeightMapShape3D.new()
	shape.map_width = W
	shape.map_depth = W
	var data := PackedFloat32Array()
	data.resize(W * W)
	shape.map_data = data
	var body := StaticBody3D.new()
	add_child_autofree(body)
	_grid = TerrainGrid.new()
	_grid.height_map = shape
	_grid.terrain_body = body
	add_child_autofree(_grid)
	var region := NavigationRegion3D.new()
	add_child_autofree(region)
	_nav = NavManager.new()
	_nav.navigation_region = region
	_nav.terrain_grid = _grid
	add_child_autofree(_nav)
	for _i: int in MAX_READY_FRAMES:
		if _nav.is_ready():
			break
		await get_tree().physics_frame


## World position of the centre of cell (x, z) on the fixture map.
func _cell_world(a_x: int, a_z: int) -> Vector3:
	var half: float = (W - 1) * 0.5
	return Vector3(a_x + 0.5 - half, 0.0, a_z + 0.5 - half)


func _sync() -> void:
	var nav_map: RID = _nav.navigation_region.get_navigation_map()
	for _i: int in SYNC_FRAMES:
		await get_tree().physics_frame
		NavigationServer3D.map_force_update(nav_map)


func _path_length(a_from: Vector3, a_to: Vector3, a_layers: int) -> float:
	var nav_map: RID = _nav.navigation_region.get_navigation_map()
	var path: PackedVector3Array = NavigationServer3D.map_get_path(
		nav_map, a_from, a_to, true, a_layers
	)
	if path.is_empty() or VU.inXZ(path[path.size() - 1]).distance_to(VU.inXZ(a_to)) > 0.5:
		return INF
	var total: float = 0.0
	for i: int in range(1, path.size()):
		total += path[i].distance_to(path[i - 1])
	return total


func _every_layer() -> Array[int]:
	var layers: Array[int] = [NavManager._BASE_LAYER]
	for size: int in NavAgentClass.Size.values():
		layers.append(_nav.layer_for(size))
	return layers


func test_the_map_is_several_chunks_wide() -> void:
	assert_true(_nav.is_ready(), "the fixture navmesh became queryable")
	assert_eq(_nav.base_polygon_count(), (W - 1) * (W - 1), "one polygon per cell, over all chunks")


func test_a_straight_path_crosses_every_chunk_border_on_every_mesh() -> void:
	var from: Vector3 = _cell_world(3, ROW)
	var to: Vector3 = _cell_world(W - 5, ROW)
	for layers: int in _every_layer():
		var length: float = _path_length(from, to, layers)
		assert_lt(length, from.distance_to(to) * MAX_PATH_EXCESS, "layers %d" % layers)


func test_a_placement_is_routed_around_and_its_removal_restores_the_path() -> void:
	var from: Vector3 = _cell_world(3, ROW)
	var to: Vector3 = _cell_world(W - 5, ROW)
	# A wall across the row, straddling a base chunk border, with room to go round either end.
	var wall: Array = []
	var border: int = NavManager.CHUNK_SIZE_CELLS
	for z: int in range(ROW - 6, ROW + 7):
		wall.append(Vector2i(border - 1, z))
		wall.append(Vector2i(border, z))
	var owner: Node = autofree(Node.new())
	_grid.place_building(wall, owner)
	var probes: Array[Vector3] = [_cell_world(border, ROW)]
	assert_true(await _nav.await_excluded(probes), "the wall's cells leave the navmesh")
	for layers: int in _every_layer():
		var detour: float = _path_length(from, to, layers)
		assert_lt(detour, INF, "still reachable around the wall, layers %d" % layers)
		assert_gt(
			detour, from.distance_to(to) * MAX_PATH_EXCESS, "routed around, layers %d" % layers
		)

	_grid.remove_building(owner)
	await get_tree().process_frame
	await _sync()
	for layers: int in _every_layer():
		assert_lt(
			_path_length(from, to, layers),
			from.distance_to(to) * MAX_PATH_EXCESS,
			"straight again once the wall is gone, layers %d" % layers
		)


## Every chunk region the manager has made. Read through `_meshes` because the regions are
## server RIDs, not nodes — which is exactly why a tree walk cannot reach them.
func _chunk_regions(a_nav: NavManager) -> Array[RID]:
	var found: Array[RID] = []
	for mesh: NavManager.ChunkedMesh in a_nav._meshes:
		for region: RID in mesh.regions.values():
			found.append(region)
	return found


func _async_flags(a_nav: NavManager) -> Array:
	return _chunk_regions(a_nav).map(
		func(r: RID) -> bool: return NavigationServer3D.region_get_use_async_iterations(r)
	)


## Replay needs every navmesh change to land on the tick that asked for it, so navigation is
## synchronous project-wide (project.godot). Asserted on the chunk regions, which NavManager makes
## by RID rather than as nodes — the case a setting could plausibly miss — and on the map.
## An async region lands its mesh whenever its worker finishes: see selfplay-harness.md
## §Determinism for the one-seed-two-matches bug that caused.
func test_the_navmesh_is_synchronous() -> void:
	var nav_map: RID = _nav.navigation_region.get_navigation_map()
	assert_false(NavigationServer3D.map_get_use_async_iterations(nav_map), "the map")
	assert_false(_async_flags(_nav).is_empty(), "the build made regions")
	assert_true(
		_async_flags(_nav).all(func(f: bool) -> bool: return not f), "and every chunk region"
	)
