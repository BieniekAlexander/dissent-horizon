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
		func(d): return Entity.entity_from_collider(d['collider'])
	).filter(func(e): return e != null)

static func linf_distance(pos1: Vector2i, pos2: Vector2i) -> int:
	var diff = (pos1 - pos2).abs()
	return max(diff.x, diff.y)

## Tests whether the attacker is in range to fire the given weapon at target,
## via a physics shape overlap against the weapon's AttackRange shape. Every
## weapon — including short-reach "melee" ones — carries an AttackRange shape
## (melee weapons just use one only slightly larger than their body), so there
## is no separate distance-based fallback.
## The shape is placed at the attacker's world transform rather than reading
## global_transform off the CollisionShape3D node directly, because Weapon and
## Loadout are plain Nodes (not Node3D) and would always report the origin.
static func is_in_attack_range(weapon: Weapon, attacker: Entity, target: Entity) -> bool:
	return is_weapon_in_range_at(weapon, attacker.global_transform, attacker.get_world_3d(), target, attacker)

## Same range check but with an explicit firing position. Used when the weapon
## belongs to a garrisoned unit firing from a shelter owner's location.
static func is_weapon_in_range_at(
	weapon: Weapon,
	from_transform: Transform3D,
	world_3d: World3D,
	target: Entity,
	exclude: Object = null
) -> bool:
	if weapon == null or weapon.attack_range_shape == null:
		return false
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = weapon.attack_range_shape.shape
	params.transform = from_transform
	params.collision_mask = CollisionLayers.Mask.TARGETABLE
	if exclude != null:
		params.exclude = [exclude]
	var results: Array = world_3d.direct_space_state.intersect_shape(params)
	return results.any(func(r: Dictionary) -> bool: return Entity.entity_from_collider(r["collider"]) == target)

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

static func unit_is_close_to_position(a_unit: Commandable, a_position: Vector2, _distance_squared: float = .001) -> bool:
	# The navigation agent stops at the destination rather than overshooting, so
	# arrival is just a position-equality check — no collision radius needed.
	return a_unit.xz_position.is_equal_approx(a_position)

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
	# Engagement proximity: measured against each entity's TARGETABLE shape edge
	# in the direction of the other, so the comparison fits each body's actual
	# shape (a box reports its edge, not its circumscribed circle).
	var t := CollisionLayers.Mask.TARGETABLE
	var combined_extent: float = an_entity.collision_extent_toward(a_unit.xz_position, t) \
		+ a_unit.collision_extent_toward(an_entity.xz_position, t)
	return (
		an_entity.xz_position - a_unit.xz_position
	).length_squared() - combined_extent**2 < distance_squared

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


## How far (in XZ world units) a candidate point may drift from the navmesh
## closest-point snap before it is considered off-navmesh.  Half a cell width
## (CELL_SIZE = 1.0) keeps points well inside valid navmesh quads.
const _NAV_SNAP_TOLERANCE: float = 0.5

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

	# The footprint each candidate point must be free of. Built once and reused
	# across every free-space probe; a sphere of point_radius approximates the
	# circular spacing the sampler lays out below.
	var probe_shape := SphereShape3D.new()
	probe_shape.radius = point_radius

	# Seed with center if it lands on a valid nav surface and is free.
	var center_ground := _project_to_nav_surface(map, center)
	if center_ground != Vector3.INF and _shape_has_space(Transform3D(Basis(), center_ground), probe_shape, world_3d, collision_mask):
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
			if _shape_has_space(Transform3D(Basis(), ground_pos), probe_shape, world_3d, collision_mask):
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

## Returns true if `shape`, placed at `shape_transform`, overlaps nothing on
## `collision_mask`. The caller supplies both the collision shape and its full
## transform, so placement is tested against the body's actual footprint and
## orientation — any Shape3D works, not just circular ones (a rotated box is
## probed as a rotated box rather than collapsed to an axis-aligned bound).
static func _shape_has_space(
	shape_transform: Transform3D,
	shape: Shape3D,
	world_3d: World3D,
	collision_mask: int
) -> bool:
	var space_state := world_3d.direct_space_state

	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = shape_transform
	params.collision_mask = collision_mask
	params.collide_with_areas = true
	params.collide_with_bodies = true

	var results: Array = space_state.intersect_shape(params, 1)
	return results.is_empty()
