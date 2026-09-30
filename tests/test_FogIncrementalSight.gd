extends GutTest

## THE INCREMENTAL FOG MUST SHOW EXACTLY WHAT A FROM-SCRATCH REBUILD WOULD.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_FogIncrementalSight.gd -gexit
##
## Fog keeps a per-pixel count of the vision sources covering it and re-stamps only a source
## whose stamp changed, instead of rebuilding every commander's fog each tick. This file runs
## random moves, captures, removals and footprint changes against a reference that rebuilds
## the way the fog used to, and requires identical display and explored bytes after every step.
## Why: gdd/systems/combat/scan-and-vision-cost.md §The fog of war.
##
## The Fog is given its image dimensions directly, with no Map: sight stamping needs none.
##
## PATHS, not preloads (see CLAUDE.md).

const IRREGULAR: Dictionary = FakePieces.BUILDER
const VIEWER: int = 3
const OTHER: int = 4
const SIZE_PX: int = 48
const SOURCE_COUNT: int = 6
const STEPS: int = 200
const SEED: int = 20260926

var _fog: Fog
var _sources: Array[Commandable] = []
var _viewer: Commander
var _other: Commander
## The reference fog's explored bytes: every pixel ever in sight, rebuilt the old way.
var _ref_explored: PackedByteArray


func before_each() -> void:
	Fog._fogs_by_commander.clear()
	_viewer = _commander(VIEWER)
	_other = _commander(OTHER)
	_fog = Fog.new()
	_fog.watching_commander_id = VIEWER
	add_child_autofree(_fog)
	_fog.set_physics_process(false)
	_fog._img_width = SIZE_PX
	_fog._img_height = SIZE_PX
	_fog._world_half_w = SIZE_PX * 0.5
	_fog._world_half_d = SIZE_PX * 0.5
	_fog._center = Vector2.ZERO
	_fog._allocate_buffers()
	_ref_explored = _fog._explored_bytes.duplicate()
	_sources.clear()


func after_each() -> void:
	Fog._fogs_by_commander.clear()


func _commander(a_id: int) -> Commander:
	var c := Commander.new()
	c.id = a_id
	add_child_autofree(c)
	return c


func _unit(a_owner: Commander, a_at: Vector3) -> Commandable:
	var u := FakePieces.make(IRREGULAR) as Commandable
	add_child_autofree(u)
	u.ownership.commander = a_owner
	u.global_position = a_at
	return u


func _los() -> Array:
	return get_tree().get_nodes_in_group("los")


## The display bytes the pre-count fog built each tick: explored, with every current
## source's footprint cleared. Also accumulates `_ref_explored`, as it did.
func _reference_display() -> PackedByteArray:
	var display: PackedByteArray = _ref_explored.duplicate()
	for entity: Entity in _los():
		if entity.commander_id != VIEWER or not entity.grants_vision():
			continue
		var pixel: Vector2i = _fog._world_to_pixel(VU.inXZ(entity.vision_range_shape.global_position))
		for offset: Vector2i in _fog._vision_offsets(entity.vision_range_shape):
			var p: Vector2i = pixel + offset
			if p.x < 0 or p.x >= SIZE_PX or p.y < 0 or p.y >= SIZE_PX:
				continue
			display[p.y * SIZE_PX + p.x] = 0
			_ref_explored[p.y * SIZE_PX + p.x] = Fog.EXPLORED_ALPHA
	return display


func _random_point(a_rng: RandomNumberGenerator) -> Vector3:
	var half: float = SIZE_PX * 0.5
	# Past the edges on purpose: a footprint clipped by the image edge must undo cleanly.
	return Vector3(a_rng.randf_range(-half - 4.0, half + 4.0), 0.0,
		a_rng.randf_range(-half - 4.0, half + 4.0))


## One random change a vision source can undergo.
func _mutate(a_rng: RandomNumberGenerator) -> void:
	var unit: Commandable = _sources[a_rng.randi_range(0, _sources.size() - 1)]
	match a_rng.randi_range(0, 5):
		0, 1:
			unit.global_position = _random_point(a_rng)
		2:
			unit.global_position += Vector3(a_rng.randf_range(-1.5, 1.5), 0.0,
				a_rng.randf_range(-1.5, 1.5))
		3:
			unit.ownership.commander = _other if unit.commander_id == VIEWER else _viewer
		4:
			# Leaving and rejoining the group: what death and garrisoning look like to fog.
			if unit.is_in_group("los"):
				unit.remove_from_group("los")
			else:
				unit.add_to_group("los")
		5:
			var shape := unit.vision_range_shape.shape.duplicate() as Shape3D
			if shape is CylinderShape3D:
				(shape as CylinderShape3D).radius = a_rng.randf_range(1.0, 9.0)
			unit.vision_range_shape.shape = shape


func test_counts_match_a_from_scratch_rebuild_through_random_changes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for i: int in SOURCE_COUNT:
		_sources.append(_unit(_viewer if i % 3 != 2 else _other, _random_point(rng)))
	var mismatches: int = 0
	for step: int in STEPS:
		if step > 0:
			_mutate(rng)
		_fog._update_sight(_los())
		var expected: PackedByteArray = _reference_display()
		if _fog._fog_bytes != expected or _fog._explored_bytes != _ref_explored:
			mismatches += 1
	assert_eq(mismatches, 0, "display and explored bytes equal the rebuild after every step")


func test_every_count_returns_to_zero_when_every_source_is_gone() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for i: int in SOURCE_COUNT:
		_sources.append(_unit(_viewer, _random_point(rng)))
	for step: int in STEPS:
		_mutate(rng)
		_fog._update_sight(_los())
	for unit: Commandable in _sources:
		unit.remove_from_group("los")
	_fog._update_sight(_los())
	var nonzero: int = 0
	for count: int in _fog._sight_counts:
		if count != 0:
			nonzero += 1
	assert_eq(nonzero, 0, "no pixel is left in sight by a source that has gone")
	assert_eq(_fog._stamps.size(), 0)
	assert_false(_fog._fog_bytes.has(0), "every explored pixel reads explored, not in sight")


func test_an_unchanged_source_leaves_the_texture_clean() -> void:
	_sources.append(_unit(_viewer, Vector3.ZERO))
	_fog._update_sight(_los())
	_fog._is_texture_stale = false
	_fog._update_sight(_los())
	assert_false(_fog._is_texture_stale, "nothing moved, so nothing needs uploading")
	_sources[0].global_position = Vector3(5.0, 0.0, 0.0)
	_fog._update_sight(_los())
	assert_true(_fog._is_texture_stale)


func test_a_reveal_shows_at_once_where_nothing_is_in_sight() -> void:
	_fog.reveal_region(Vector2.ZERO, 3.0)
	var idx: int = _fog._world_to_pixel(Vector2.ZERO).y * SIZE_PX \
		+ _fog._world_to_pixel(Vector2.ZERO).x
	assert_eq(_fog._explored_bytes[idx], Fog.EXPLORED_ALPHA)
	assert_eq(_fog._fog_bytes[idx], Fog.EXPLORED_ALPHA, "the display follows the reveal")


## A Map whose cells sit one world unit apart on the XZ plane, so a footprint needs no terrain.
class FlatMap extends Map:
	func grid_to_world(a_cell: Vector2i) -> Vector3:
		return Vector3(a_cell.x, 0.0, a_cell.y)


func _pixel_index(a_cell: Vector2i) -> int:
	var pixel: Vector2i = _fog._world_to_pixel(Vector2(a_cell.x, a_cell.y))
	return pixel.y * SIZE_PX + pixel.x


func test_a_structure_is_seen_through_its_memoized_footprint_and_follows_a_new_one() -> void:
	var map := FlatMap.new()
	_fog._map = map
	var structure := Node3D.new()
	add_child_autofree(structure)
	map.structure_cell_map[structure] = [Vector2i(0, 0), Vector2i(1, 0)]
	assert_false(_fog.structure_in_vision(structure), "nothing in sight yet")
	_fog._fog_bytes[_pixel_index(Vector2i(1, 0))] = 0
	assert_true(_fog.structure_in_vision(structure), "any footprint cell in sight counts")
	# Map REPLACES an entry when a footprint changes; the memo must follow the new array.
	map.structure_cell_map[structure] = [Vector2i(5, 5)]
	assert_false(_fog.structure_in_vision(structure), "the old footprint no longer counts")
	_fog._fog_bytes[_pixel_index(Vector2i(5, 5))] = 0
	assert_true(_fog.structure_in_vision(structure))
	_fog._map = null
	map.free()
