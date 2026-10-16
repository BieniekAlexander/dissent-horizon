extends GutTest

## HeightmapRay — whether a segment touches a heightmap's surface, answered without the physics
## server. Held to the physics server itself: random segments over a random heightmap must get
## the same answer from both, which is also what pins the triangle diagonal
## (HeightmapRay.DIAGONAL_FROM_X1_Z0).

const SIZE: int = 16
const MAX_HEIGHT: float = 3.0
const SEGMENTS: int = 2000
const SEED: int = 20261016
## Where the body stands: off the origin, so the world-to-local transform is exercised.
const BODY_AT: Vector3 = Vector3(5.0, 1.5, -3.0)


func _heightmap(a_rng: RandomNumberGenerator) -> HeightMapShape3D:
	var shape := HeightMapShape3D.new()
	shape.map_width = SIZE
	shape.map_depth = SIZE
	var data := PackedFloat32Array()
	for _i: int in SIZE * SIZE:
		data.append(a_rng.randf() * MAX_HEIGHT)
	shape.map_data = data
	return shape


## Every segment that starts above the surface — the only kind the line of fire casts — gets
## the physics server's answer. (Starting under it, the server is not consistent; see
## HeightmapRay.)
func test_it_agrees_with_the_physics_ray_on_random_segments() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var shape: HeightMapShape3D = _heightmap(rng)
	var body := StaticBody3D.new()
	body.position = BODY_AT
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child_autofree(body)
	await wait_physics_frames(2)
	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	var half: float = (SIZE - 1) * 0.5
	var compared: int = 0
	var disagreements: Array = []
	for _i: int in SEGMENTS:
		var from: Vector3 = BODY_AT + _random_offset(rng, half)
		var to: Vector3 = BODY_AT + _random_offset(rng, half)
		if not _is_above_surface(space, body, from):
			continue
		compared += 1
		var query := PhysicsRayQueryParameters3D.create(from, to, body.collision_layer)
		var physics: bool = not space.intersect_ray(query).is_empty()
		if physics != HeightmapRay.hits(shape, body.global_transform, from, to):
			disagreements.append([from, to, physics])
	assert_gt(compared, SEGMENTS / 4, "enough segments start above the surface to mean something")
	assert_eq(disagreements.size(), 0, "first disagreements: %s" % [disagreements.slice(0, 3)])


func _random_offset(a_rng: RandomNumberGenerator, a_half: float) -> Vector3:
	return Vector3(
		a_rng.randf_range(-a_half, a_half),
		a_rng.randf_range(-0.5, MAX_HEIGHT + 1.0),
		a_rng.randf_range(-a_half, a_half)
	)


## Whether `a_point` stands above the surface, by a vertical physics ray from far above it.
func _is_above_surface(
	a_space: PhysicsDirectSpaceState3D, a_body: StaticBody3D, a_point: Vector3
) -> bool:
	var top: Vector3 = Vector3(a_point.x, a_point.y + 100.0, a_point.z)
	var bottom: Vector3 = Vector3(a_point.x, a_point.y - 100.0, a_point.z)
	var hit: Dictionary = a_space.intersect_ray(
		PhysicsRayQueryParameters3D.create(top, bottom, a_body.collision_layer)
	)
	return hit.is_empty() or a_point.y > (hit["position"] as Vector3).y
