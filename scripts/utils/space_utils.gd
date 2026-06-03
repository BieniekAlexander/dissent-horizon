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

## Tests whether the attacker is in range to fire the given weapon at target.
## Ranged weapons (attack_range_shape != null): physics shape overlap test.
## Melee weapons (attack_range_shape == null): XZ centre-to-centre distance.
## The shape is placed at the attacker's world transform rather than reading
## global_transform off the CollisionShape3D node directly, because Weapon and
## Loadout are plain Nodes (not Node3D) and would always report the origin.
static func is_in_attack_range(weapon: Weapon, attacker: Entity, target: Entity) -> bool:
	if weapon == null:
		return false
	if weapon.attack_range_shape != null:
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = weapon.attack_range_shape.shape
		params.transform = attacker.global_transform
		params.exclude = [attacker]
		var results: Array = attacker.get_world_3d().direct_space_state.intersect_shape(params)
		return results.any(func(r: Dictionary) -> bool: return r["collider"] == target)
	else:
		return attacker.xz_position.distance_to(target.xz_position) <= weapon.melee_range

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

static func unit_is_close_to_structure(a_unit: Commandable, a_structure: Commandable, _distance_squared: float = .001) -> bool:
	# A unit counts as close to a structure when its grid cell lies within the
	# structure's footprint or is immediately adjacent to it. Measuring against
	# the whole footprint (rather than the structure's single origin cell) makes
	# proximity scale with the building's size: otherwise a builder/collector
	# would have to stand *on* a cell the structure itself occupies, which is
	# impossible for anything larger than 1x1 — the old same-cell check could
	# never succeed for a multi-cell structure, so a builder could never finish
	# (Repair) a large building it had just placed.
	var placement_map: Map = a_structure.map
	if placement_map == null:
		return linf_distance(VU.inXZ(a_unit.global_position), VU.inXZ(a_structure.global_position)) <= 1
	var unit_cell: Vector2i = placement_map.world_to_grid(VU.inXZ(a_unit.global_position))
	var footprint: Array = placement_map.structure_cell_map.get(a_structure, [])
	if footprint.is_empty():
		# Footprint not registered yet — fall back to the structure's origin cell.
		return linf_distance(unit_cell, placement_map.world_to_grid(VU.inXZ(a_structure.global_position))) <= 1
	for cell in footprint:
		if linf_distance(unit_cell, cell) <= 1:
			return true
	return false

static func unit_is_close_to_unit(a_unit: Commandable, an_entity: Entity, distance_squared: float = .001) -> bool:
	# specifically checks that the borders of the cillision circles is less than some distance
	return (
		an_entity.xz_position - a_unit.xz_position
	).length_squared() - (an_entity.collision_radius+a_unit.collision_radius)**2 < distance_squared

## ── UNIT PLACEMENT ──────────────────────────────────────────────────────────
##
## The functions below answer the question: "If this unit enters the scene
## near an existing entity, where should it appear so it doesn't overlap?"
## They are intentionally generic so the same logic can serve garrisoning,
## structure exit, unit training, teleport landing, etc.

## Return all unique grid cells that are directly adjacent (L∞-distance 1) to
## any cell in `a_structure`'s footprint, are in-bounds, and are currently
## passable (not occupied by another structure, not too steep).  The returned
## list is shuffled so callers can pop_front() to assign distinct destinations
## without bias.
static func passable_cells_adjacent_to(a_structure: Commandable, a_map: Map) -> Array[Vector2i]:
	if a_structure == null or a_map == null:
		return []

	var footprint: Array = a_map.structure_cell_map.get(a_structure, [])
	# `seen` prevents both footprint cells and already-collected neighbors
	# from appearing in the output.
	var seen: Dictionary = {}
	for cell in footprint:
		seen[cell] = true

	var result: Array[Vector2i] = []
	for cell: Vector2i in footprint:
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				if dx == 0 and dz == 0:
					continue
				var neighbor := Vector2i(cell.x + dx, cell.y + dz)
				if seen.has(neighbor):
					continue
				if not a_map.grid_coordinates_in_bounds(neighbor):
					continue
				if not a_map.terrain_grid.is_passable(neighbor):
					continue
				seen[neighbor] = true
				result.append(neighbor)

	result.shuffle()
	return result


## Return the grid cell adjacent to `a_structure`'s footprint — in-bounds and
## passable — whose world-space centre is closest to `dest`.
## Returns Vector2i(-1, -1) when no suitable cell exists.
static func nearest_footprint_adjacent_cell(
	dest: Vector3,
	a_structure: Commandable,
	a_map: Map
) -> Vector2i:
	if a_structure == null or a_map == null:
		return Vector2i(-1, -1)

	var footprint: Array = a_map.structure_cell_map.get(a_structure, [])
	var in_footprint: Dictionary = {}
	for cell in footprint:
		in_footprint[cell] = true

	var best_cell := Vector2i(-1, -1)
	var best_dist_sq := INF

	for cell: Vector2i in footprint:
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				if dx == 0 and dz == 0:
					continue
				var neighbor := Vector2i(cell.x + dx, cell.y + dz)
				if in_footprint.has(neighbor):
					continue
				if not a_map.grid_coordinates_in_bounds(neighbor):
					continue
				if not a_map.terrain_grid.is_passable(neighbor):
					continue
				var dist_sq := a_map.grid_to_world(neighbor).distance_squared_to(dest)
				if dist_sq < best_dist_sq:
					best_dist_sq = dist_sq
					best_cell = neighbor

	return best_cell


## Return the world-space spawn position for the unit at `index` (0-based) in
## a ring of `total` units placed around `center`.  The ring radius is just
## large enough to clear both entities' Layer.BODY collision spheres so no
## overlap occurs at spawn time.  Y is snapped to terrain height plus the
## unit's height offset.
static func ring_spawn_position(
	center: Commandable,
	unit: Commandable,
	index: int,
	total: int,
	a_map: Map
) -> Vector3:
	const BODY_BUFFER: float = 0.15
	var ring_radius: float = center.collision_radius + unit.collision_radius + BODY_BUFFER

	var angle: float = 2.0 * PI * float(index) / float(max(total, 1))
	var xz: Vector2 = VU.inXZ(center.global_position) \
		+ Vector2(cos(angle), sin(angle)) * ring_radius

	var height_offset: float = unit.movement.height_offset() if unit.movement != null else 0.0
	var y: float = a_map.terrain_height_at(xz) + height_offset \
		if a_map != null else center.global_position.y

	return Vector3(xz.x, y, xz.y)


## How far (in XZ world units) a candidate point may drift from the navmesh
## closest-point snap before it is considered off-navmesh.  Half a cell width
## (CELL_SIZE = 2.0) keeps points well inside valid navmesh quads.
const _NAV_SNAP_TOLERANCE: float = 1.0

static func get_nonoverlapping_points(
	map: Map,
	center: Vector2,
	point_radius: float,
	world_3d: World3D,
	collision_mask: int,
	region_radius: float,
	max_points: int = 1,
	sample_count: int = 10,
) -> Array[Vector2]:
	var about_points: Array[Vector2] = []
	var ret_points: Array[Vector2] = []

	# Seed with center if it lands on a valid nav surface and is free.
	var center_ground := _project_to_nav_surface(map, center)
	if center_ground != Vector3.INF and _is_point_free_3d(center_ground, point_radius, world_3d, collision_mask):
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
			var ground_pos := _project_to_nav_surface(map, new_point)
			if ground_pos == Vector3.INF:
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

## Project an XZ world position onto the navmesh using NavigationServer3D.
## Returns the snapped Vector3 if the closest navmesh point is within
## _NAV_SNAP_TOLERANCE in XZ; returns Vector3.INF if the point is off-navmesh
## (e.g. over a building cell, outside map bounds, etc.).
static func _project_to_nav_surface(map: Map, point_xz: Vector2) -> Vector3:
	var nav_map := map.nav_region.get_navigation_map()
	var probe := Vector3(point_xz.x, map.terrain_height_at(point_xz), point_xz.y)
	var snapped := NavigationServer3D.map_get_closest_point(nav_map, probe)
	var snapped_xz := Vector2(snapped.x, snapped.z)
	if snapped_xz.distance_to(point_xz) > _NAV_SNAP_TOLERANCE:
		return Vector3.INF  # candidate is off the navmesh
	return snapped

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
