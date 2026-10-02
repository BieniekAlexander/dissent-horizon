extends GutTest

## Pins Map's cached world→local transform (Map.world_to_local_transform).
##
## Two things are under test, and the second is an ENGINE behaviour the cache depends on:
## the cached inverse must agree with inverting global_transform on every read, and
## NOTIFICATION_TRANSFORM_CHANGED — the thing that invalidates it — is delivered a frame
## LATE, not synchronously. See the comment above Map._world_to_local.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_MapTransformCache.gd

const W: int = 9  # 9x9 corners; height == corner x index, so height varies along X


class StubMap:
	extends Map

	# Map._ready builds a TerrainGrid / NavManager and asserts on scene children we don't
	# want here — this test only exercises the coordinate helpers.
	func _ready() -> void:
		pass


var _world: Node3D
var _map: StubMap


func before_each() -> void:
	_world = Node3D.new()
	_map = StubMap.new()
	var heights := PackedFloat32Array()
	heights.resize(W * W)
	for z: int in W:
		for x: int in W:
			heights[z * W + x] = float(x)
	var shape := HeightMapShape3D.new()
	shape.map_width = W
	shape.map_depth = W
	shape.map_data = heights
	_map.height_map = shape
	_world.add_child(_map)
	add_child_autofree(_world)


## The value the cache must reproduce: the same bilinear read against a freshly
## inverted global_transform.
func _uncached_height(a_map: Map, a_world_xz: Vector2) -> float:
	var hs: HeightMapShape3D = a_map.height_map
	var hw: float = (hs.map_width - 1) * 0.5
	var hd: float = (hs.map_depth - 1) * 0.5
	var local: Vector3 = (
		a_map.global_transform.affine_inverse() * Vector3(a_world_xz.x, 0.0, a_world_xz.y)
	)
	var lx: float = clampf(local.x + hw, 0.0, hs.map_width - 1)
	var lz: float = clampf(local.z + hd, 0.0, hs.map_depth - 1)
	var x0: int = floori(lx)
	var z0: int = floori(lz)
	var x1: int = mini(x0 + 1, hs.map_width - 1)
	var z1: int = mini(z0 + 1, hs.map_depth - 1)
	var fx: float = lx - x0
	var fz: float = lz - z0
	var h: float = lerpf(
		lerpf(hs.map_data[z0 * hs.map_width + x0], hs.map_data[z0 * hs.map_width + x1], fx),
		lerpf(hs.map_data[z1 * hs.map_width + x0], hs.map_data[z1 * hs.map_width + x1], fx),
		fz
	)
	return (a_map.global_transform * Vector3(local.x, h, local.z)).y


func test_cached_transform_equals_a_fresh_inverse():
	assert_eq(_map.world_to_local_transform(), _map.global_transform.affine_inverse())


func test_heights_match_the_uncached_computation():
	for p: Vector2 in [Vector2(0, 0), Vector2(2.5, -1.5), Vector2(-3.25, 3.75)]:
		assert_almost_eq(
			_map.terrain_height_at(p), _uncached_height(_map, p), 0.0001, "height at %v" % p
		)


func test_repeated_reads_are_stable():
	var first: float = _map.terrain_height_at(Vector2(1.5, 0.0))
	for _i: int in 10:
		assert_almost_eq(_map.terrain_height_at(Vector2(1.5, 0.0)), first, 0.0001)


## Corner x=0 sits at local x = -(W-1)/2 = -4, and height == x, so world x=0 reads 4.0.
func test_identity_transform_reads_the_authored_ramp():
	assert_almost_eq(_map.terrain_height_at(Vector2(0.0, 0.0)), 4.0, 0.0001)


## Moving the Map shifts which corner sits under a fixed world point — once the transform
## notification has been flushed.
func test_moving_the_map_updates_heights_after_a_frame():
	_map.position = Vector3(2.0, 0.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_almost_eq(_map.terrain_height_at(Vector2(0.0, 0.0)), 2.0, 0.0001)
	assert_eq(_map.world_to_local_transform(), _map.global_transform.affine_inverse())


## A Y translation rides through global_transform on the way back out.
func test_vertical_offset_applies_to_sampled_height():
	_map.position = Vector3(0.0, 3.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_almost_eq(_map.terrain_height_at(Vector2(0.0, 0.0)), 7.0, 0.0001)


## Moving a PARENT invalidates too — the notification propagates down the tree.
func test_moving_an_ancestor_updates_heights():
	_world.position = Vector3(2.0, 0.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_almost_eq(_map.terrain_height_at(Vector2(0.0, 0.0)), 2.0, 0.0001)


## The engine behaviour the cache's one-frame lag is built on: the notification does NOT
## arrive synchronously, so an immediate read still sees the old transform. Pinned so a
## future engine change (or a caller that starts moving the Map) surfaces here.
func test_transform_notification_is_not_synchronous():
	var before: float = _map.terrain_height_at(Vector2(0.0, 0.0))
	_map.position = Vector3(2.0, 0.0, 0.0)
	assert_almost_eq(
		_map.terrain_height_at(Vector2(0.0, 0.0)),
		before,
		0.0001,
		"read before the transform flush should still see the cached frame"
	)
	# invalidate_transform_cache is the escape hatch for exactly this case.
	_map.invalidate_transform_cache()
	assert_almost_eq(_map.terrain_height_at(Vector2(0.0, 0.0)), 2.0, 0.0001)
