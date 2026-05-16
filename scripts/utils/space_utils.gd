# Utilities that deal with the relationships of things in space
# I'm hoping this will make my distance calculations more expressive,
# e.g. checking if a unit is adjacent to a structure, which sits on a set of hex cells
class_name SU

static var rng = RandomNumberGenerator.new()

static func get_nearby_entities(world_3d: World3D, a_position: Vector3, a_radius: float, collision_mask: int) -> Array:
	var shape := SphereShape3D.new()
	shape.radius = a_radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform.origin = a_position
	params.collision_mask = collision_mask
	return world_3d.direct_space_state.intersect_shape(params, 10).map(
		func(d): return d['collider']
	)

static func linf_distance(pos1: Vector2i, pos2: Vector2i) -> int:
	var diff = (pos1 - pos2).abs()
	return max(diff.x, diff.y)

## Tests whether the attacker's AttackRange shape overlaps the target's physics
## body. Shape selection is delegated to _get_attack_range_shape so unit scripts
## can swap in a different shape per target (e.g. flying vs grounded attack types).
static func is_in_attack_range(attacker: Entity, target: Entity) -> bool:
	var range_shape: CollisionShape3D = attacker._get_attack_range_shape(target)
	if range_shape == null:
		return false
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = range_shape.shape
	params.transform = range_shape.global_transform
	params.exclude = [attacker]
	var results: Array = attacker.get_world_3d().direct_space_state.intersect_shape(params)
	return results.any(func(r: Dictionary) -> bool: return r["collider"] == target)

static func unit_is_close_to_target(a_unit: Commandable, a_target: Variant, distance_squared: float = .001) -> bool:
	if a_target is Commandable and a_target.is_in_group("structure"):
		return SU.unit_is_close_to_structure(a_unit, a_target, distance_squared)
	elif a_target is Entity:
		return SU.unit_is_close_to_unit(a_unit, a_target, distance_squared)
	elif a_target is Vector2:
		return SU.unit_is_close_to_position(a_unit, a_target, distance_squared)
	else:
		push_error("unsuported distance target type")
		return false

static func unit_is_close_to_position(a_unit: Commandable, a_position: Vector2, distance_squared: float = .001) -> bool:
	# TODO
	push_error("TODO")
	# specifically checks that the borders of the cillision circles is less than some distance
	return (
		a_position - a_unit.xz_position
	).length_squared() - a_unit.collision_radius**2 < distance_squared

static func unit_is_close_to_structure(a_unit: Commandable, a_structure: Commandable, distance_squared: float = .001) -> bool:
	# specifically checks that the borders of the cillision circles is less than some distance
	return linf_distance(
		VU.inXZ(a_unit.global_position), VU.inXZ(a_structure.global_position)
	) < distance_squared

static func unit_is_close_to_unit(a_unit: Commandable, an_entity: Entity, distance_squared: float = .001) -> bool:
	# specifically checks that the borders of the cillision circles is less than some distance
	return (
		an_entity.xz_position - a_unit.xz_position
	).length_squared() - (an_entity.collision_radius+a_unit.collision_radius)**2 < distance_squared

static func get_nonoverlapping_points(
	map: Map,
	center: Vector2,
	point_radius: float,
	world_3d: World3D,
	collision_mask: int,
	nav_layer_mask: int,
	region_radius: float,
	max_points: int = 1,
	sample_count: int = 10,
	raycast_height: float = 50.0,
	raycast_max_depth: float = 200.0
) -> Array[Vector2]:
	var about_points: Array[Vector2] = []
	var ret_points: Array[Vector2] = []

	# Seed with center if it lands on a valid nav surface and is free.
	var center_ground := _project_to_nav_surface(center, world_3d, nav_layer_mask, raycast_height, raycast_max_depth)
	if center_ground != null and _is_point_free_3d(center_ground, point_radius, world_3d, collision_mask):
		ret_points.append(center)
		about_points.append(center)
		if max_points == 1:
			return ret_points

	while about_points.size() > 0:
		var about_point: Vector2 = about_points[0]
		var candidate_accepted := false

		for i in range(sample_count):
			var angle: float = 2.0 * PI * rng.randf()
			var vec := 2.0 * point_radius * (1.0 + rng.randf()) * Vector2(sin(angle), cos(angle))
			var new_point := about_point + vec

			# Stay inside region in XZ.
			if (new_point - center).length_squared() >= region_radius * region_radius:
				continue

			# Project this XZ onto a valid nav surface.
			var ground_pos := _project_to_nav_surface(new_point, world_3d, nav_layer_mask, raycast_height, raycast_max_depth)
			if ground_pos == null:
				continue  # not on a valid surface

			# Check for overlaps at grounded position.
			if _is_point_free_3d(ground_pos, point_radius, world_3d, collision_mask):
				about_points.insert(0, new_point)
				ret_points.append(new_point)

				if ret_points.size() == max_points:
					return ret_points

				candidate_accepted = true
				break

		if not candidate_accepted:
			about_points.remove_at(0)

	push_error("Not enough points collected - requested %s, got %s" % [max_points, ret_points.size()])
	return ret_points

static func _project_to_nav_surface(
	point_xz: Vector2,
	world_3d: World3D,
	nav_layer_mask: int,
	raycast_height: float,
	raycast_max_depth: float
) -> Vector3:
	var space_state := world_3d.direct_space_state

	var origin := Vector3(point_xz.x, raycast_height, point_xz.y)
	var target := origin + Vector3.DOWN * raycast_max_depth

	var query := PhysicsRayQueryParameters3D.create(origin, target)
	query.collide_with_bodies = true
	query.collide_with_areas = true
	# Optionally, restrict to layers that contain navigation regions/ground geometry:
	# query.collision_mask = <ground collision layers>

	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return Vector3.INF

	var collider: Variant = result['collider']

	# Try to read navigation layers. Adjust to your setup:
	var nav_layers := 0
	if collider.has_method("get_navigation_layers"):
		nav_layers = collider.get_navigation_layers()
	elif collider.has_meta("navigation_layers"):
		nav_layers = int(collider.get_meta("navigation_layers"))
	elif "navigation_layers" in collider:
		nav_layers = collider.navigation_layers

	if (nav_layers & nav_layer_mask) == 0:
		return Vector3.INF  # surface not on desired navigation layers

	return result.position

static func _is_point_free_3d(
	ground_pos: Vector3,
	radius: float,
	world_3d: World3D,
	collision_mask: int
) -> bool:
	var space_state := world_3d.direct_space_state

	var shape := SphereShape3D.new()
	shape.radius = radius

	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform.origin = ground_pos
	params.collision_mask = collision_mask
	params.collide_with_areas = true
	params.collide_with_bodies = true

	var results: Array = space_state.intersect_shape(params, 1)
	return results.is_empty()
