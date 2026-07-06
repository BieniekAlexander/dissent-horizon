# Utilities that deal with the relationships of things in space
# I'm hoping this will make my distance calculations more expressive,
# e.g. checking if a unit is adjacent to a structure, which sits on a set of hex cells
class_name SU

#region Properties
static var rng = RandomNumberGenerator.new()

const _NAV_SNAP_TOLERANCE: float = 0.5
#endregion

#region Public API
## Run a shape overlap and return the owning Entities of everything it hit on
## `collision_mask`, with nulls (non-entity colliders) dropped. The single
## chokepoint for "which entities overlap this shape" — aggro, vision, detection,
## and AoE all go through here instead of hand-rolling intersect_shape +
## entity_from_collider. `exclude` is a list of RIDs/Objects to skip.
static func query_shape_for_entities(
	world_3d: World3D,
	shape: Shape3D,
	transform: Transform3D,
	collision_mask: int,
	exclude: Array = [],
	max_results: int = 32
) -> Array[Entity]:
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = transform
	params.collision_mask = collision_mask
	params.exclude = exclude
	var result: Array[Entity] = []
	result.assign(
		world_3d.direct_space_state.intersect_shape(params, max_results).map(
			func(d: Dictionary) -> Entity: return Entity.entity_from_collider(d["collider"])
		).filter(func(e: Entity) -> bool: return e != null)
	)
	return result

static func get_nearby_entities(world_3d: World3D, a_position: Vector3, a_radius: float, collision_mask: int) -> Array:
	var shape := SphereShape3D.new()
	shape.radius = a_radius
	return query_shape_for_entities(
		world_3d, shape, Transform3D(Basis(), a_position), collision_mask, [], 10
	)

## The shared "aggro shape collision check": targetable entities overlapping
## `shape_node`'s shape re-centred at `center` (world space). Positions the aggro/query
## shape at `center` and returns everything on TARGETABLE_ANY inside it, using the real
## shape geometry (not a radius approximation) and leaving enemy/visibility/weapon
## filtering to the caller. `exclude_body` (e.g. the querying entity's own TargetBody) is
## skipped. Empty when `shape_node` or its shape is null.
static func entities_in_aggro_shape(
	world_3d: World3D,
	shape_node: CollisionShape3D,
	center: Vector3,
	exclude_body: CollisionObject3D = null,
	max_results: int = 32
) -> Array[Entity]:
	if shape_node == null or shape_node.shape == null:
		return []
	var xform: Transform3D = shape_node.global_transform
	xform.origin = center
	var exclude: Array = [exclude_body.get_rid()] if exclude_body != null else []
	return query_shape_for_entities(
		world_3d, shape_node.shape, xform, CollisionLayers.TARGETABLE_ANY, exclude, max_results
	)

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
	return (
		is_weapon_in_range_at(weapon, attacker.global_transform, attacker.get_world_3d(), target, attacker)
		if weapon!=null
		else false
	)

## Same range check but with an explicit firing position. Used when the weapon
## belongs to a garrisoned unit firing from a garrison owner's location.
static func is_weapon_in_range_at(
	weapon: Weapon,
	from_transform: Transform3D,
	world_3d: World3D,
	target: Entity,
	firer: Entity = null,
	reach_bonus: float = 0.0
) -> bool:
	var params := PhysicsShapeQueryParameters3D.new()
	# A flat reach buffer (e.g. a garrison's range_bonus) GROWS the query radius rather
	# than offsetting the origin below: growth stays centred on the firer, so an
	# arbitrarily large bonus can never overshoot a point-blank target into a dead zone
	# the way a big origin shift would. Only rebuilds the shape when a bonus applies.
	var range_shape: Shape3D = weapon.get_range_for_target(target).shape
	params.shape = _grow_shape_radius(range_shape, reach_bonus) if reach_bonus > 0.0 else range_shape
	# Surface-to-surface range. The query already reports the target's NEAR edge, but
	# it is centred on the firer, so a wide firer's own hull eats into its reach. Push
	# the query origin toward the target by the firer's own targetable extent, so reach
	# is measured from the firer's hull edge — "range R" becomes the gap between the two
	# hulls regardless of either body's size (e.g. a bunkered garrison reaches as far as
	# the units shooting into it). NOTE: PhysicsShapeQueryParameters3D.margin is a no-op
	# for intersect_shape (verified for sphere and cylinder), so we shift the transform
	# rather than inflate via margin.
	var from_t := from_transform
	if firer != null:
		var to_target: Vector2 = target.xz_position - VU.inXZ(from_transform.origin)
		if not to_target.is_zero_approx():
			var extent: float = maxf(0.0,
				firer.collision_extent_toward(target.xz_position, CollisionLayers.TARGETABLE_ANY))
			from_t.origin += VU.fromXZ(to_target.normalized() * extent)
	params.transform = from_t
	# Only scan the layers this weapon can actually hit, so e.g. a ground-only
	# weapon never reports an air target as "in range".
	params.collision_mask = weapon.target_mask
	if firer != null:
		params.exclude = [firer]
	var results: Array = world_3d.direct_space_state.intersect_shape(params)
	return results.any(func(r: Dictionary) -> bool: return Entity.entity_from_collider(r["collider"]) == target)


## Return a copy of `shape` with its radius grown by `amount`, leaving the shared
## source resource untouched. Cylinder and sphere cover every AttackRange shape in
## use; an unrecognised shape is returned unchanged (bonus silently not applied).
static func _grow_shape_radius(shape: Shape3D, amount: float) -> Shape3D:
	if shape is CylinderShape3D:
		var c: CylinderShape3D = (shape as CylinderShape3D).duplicate()
		c.radius += amount
		return c
	if shape is SphereShape3D:
		var s: SphereShape3D = (shape as SphereShape3D).duplicate()
		s.radius += amount
		return s
	return shape


static func unit_is_close_to_target(a_unit: Commandable, a_target: Variant, distance_squared: float = .001) -> bool:
	# Group-based, not type-based: a structure may be an Entity that is NOT a Commandable
	# (e.g. ShelterStructure / Deposit), and it still wants footprint-adjacency proximity
	# rather than the strict touch-the-target-body check used for mobile units.
	if a_target is Entity and a_target.is_in_group("structure"):
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

static func unit_is_close_to_structure(a_unit: Commandable, a_structure: Entity, _distance_squared: float = .001) -> bool:
	# A unit counts as close to a structure when its grid cell lies within the
	# structure's footprint or is immediately adjacent to it (see
	# unit_is_close_to_footprint). Measuring against the whole footprint makes
	# proximity scale with the building's size: otherwise a builder would have to
	# stand *on* a cell the structure occupies, impossible for anything > 1x1.
	var placement_map: Map = a_structure.map
	if placement_map == null:
		return linf_distance(VU.inXZ(a_unit.global_position), VU.inXZ(a_structure.global_position)) <= 1
	var footprint: Array = structure_footprint(placement_map, a_structure)
	if footprint.is_empty():
		# Footprint not registered yet — fall back to the structure's origin cell.
		footprint = [placement_map.world_to_grid(VU.inXZ(a_structure.global_position))]
	return unit_is_close_to_footprint(a_unit, placement_map, footprint)

## The grid cells to measure build/repair proximity against for a structure.
## Normally the structure's own registered footprint; an OVERLAY structure (a Mine,
## which doesn't occupy the grid itself) reports its host Deposit's footprint, since
## that is what it sits on. Empty if neither is registered yet.
static func structure_footprint(a_map: Map, a_structure: Entity) -> Array:
	if a_map == null or a_structure == null:
		return []
	var own: Array = a_map.structure_cell_map.get(a_structure, [])
	if not own.is_empty():
		return own
	if a_structure is Mine and (a_structure as Mine).deposit != null:
		return a_map.structure_cell_map.get((a_structure as Mine).deposit, [])
	return []

## True when a_unit's grid cell lies within (L∞ ≤ 1 of) any cell in `footprint` —
## i.e. on the footprint or immediately adjacent. The shared "close enough to
## build / repair / work on" predicate. Build measures against the would-be
## footprint (Map.footprint_cells of the clicked spot) and Repair against the
## structure's registered footprint; because add_structure registers exactly the
## cells footprint_cells returns, the two checks always agree.
static func unit_is_close_to_footprint(a_unit: Commandable, a_map: Map, footprint: Array) -> bool:
	if a_map == null or footprint.is_empty():
		return false
	var unit_cell: Vector2i = a_map.world_to_grid(VU.inXZ(a_unit.global_position))
	for cell: Vector2i in footprint:
		if linf_distance(unit_cell, cell) <= 1:
			return true
	return false

static func unit_is_close_to_unit(a_unit: Commandable, an_entity: Entity, distance_squared: float = .001) -> bool:
	# Engagement proximity: measured against each entity's targetable shape edge
	# in the direction of the other, so the comparison fits each body's actual
	# shape (a box reports its edge, not its circumscribed circle).
	var t := CollisionLayers.TARGETABLE_ANY
	var combined_extent: float = an_entity.collision_extent_toward(a_unit.xz_position, t) \
		+ a_unit.collision_extent_toward(an_entity.xz_position, t)
	return (
		an_entity.xz_position - a_unit.xz_position
	).length_squared() - combined_extent**2 < distance_squared

## Return all unique grid cells that are directly adjacent (L∞-distance 1) to
## any cell in `a_structure`'s footprint, are in-bounds, and are currently
## passable (not occupied by another structure, not too steep).  The returned
## list is shuffled so callers can pop_front() to assign distinct destinations
## without bias.
static func passable_cells_adjacent_to(a_structure: Commandable, a_map: Map) -> Array[Vector2i]:
	var result: Array[Vector2i] = _passable_footprint_neighbors(a_structure, a_map)
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
	var best_cell := Vector2i(-1, -1)
	var best_dist_sq := INF

	for neighbor in _passable_footprint_neighbors(a_structure, a_map):
		var dist_sq := a_map.grid_to_world(neighbor).distance_squared_to(dest)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_cell = neighbor

	return best_cell

## How far (in XZ world units) a candidate point may drift from the navmesh
## closest-point snap before it is considered off-navmesh.  Half a cell width
## (CELL_SIZE = 1.0) keeps points well inside valid navmesh quads.
## Scatter up to `max_points` distinct XZ points around `center`, each on the
## navmesh and clear of `collision_mask` bodies.
##
## Spacing normally uses the uniform `point_radius`. When `point_radii` is
## supplied (one entry per requested point), the point at index i is instead
## spaced and clearance-probed by ITS OWN radius, and the gap between a point and
## its neighbour is the sum of their two radii — so a mix of large and small
## bodies packs each according to its real footprint rather than inheriting one
## shared (often oversized) radius. `point_radius` remains the fallback for any
## index beyond `point_radii`'s length.
static func get_nonoverlapping_points(
	map: Map,
	center: Vector2,
	point_radius: float,
	world_3d: World3D,
	collision_mask: int,
	region_radius: float,
	max_points: int = 1,
	sample_count: int = 10,
	point_radii: Array[float] = [],
) -> Array[Vector2]:
	# Each accepted point is stored with the radius it was placed at, so its
	# children space themselves off the correct (its own) footprint.
	var about_points: Array[Vector2] = []
	var about_radii: Array[float] = []
	var ret_points: Array[Vector2] = []

	# A sphere sized per candidate; radius is reset before each free-space probe.
	var probe_shape := SphereShape3D.new()

	# Seed with center if it lands on a valid nav surface and is free.
	var seed_radius: float = _radius_at(point_radii, 0, point_radius)
	probe_shape.radius = seed_radius
	var center_ground := _project_to_nav_surface(map, center)
	if center_ground != Vector3.INF and _shape_has_space(Transform3D(Basis(), center_ground), probe_shape, world_3d, collision_mask):
		ret_points.append(center)
		about_points.append(center)
		about_radii.append(seed_radius)
		if max_points == 1:
			return ret_points

	while about_points.size() > 0:
		var about_point: Vector2 = about_points[0]
		var parent_radius: float = about_radii[0]
		# The next point to place maps to index ret_points.size() (== caller's slot).
		var new_radius: float = _radius_at(point_radii, ret_points.size(), point_radius)
		probe_shape.radius = new_radius
		var candidate_accepted := false

		for i in range(sample_count):
			var angle: float = 2.0 * PI * rng.randf()
			# Centre-to-centre gap ≥ the two bodies touching (sum of radii), up to 2×
			# that, so neighbours never overlap whatever their individual sizes.
			var spacing: float = (parent_radius + new_radius) * (1.0 + rng.randf())
			var new_point := about_point + spacing * Vector2(sin(angle), cos(angle))

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
				about_radii.insert(0, new_radius)
				ret_points.append(new_point)

				if ret_points.size() == max_points:
					return ret_points

				candidate_accepted = true
				break

		if not candidate_accepted:
			about_points.remove_at(0)
			about_radii.remove_at(0)

	push_error("Not enough points collected - requested %s, got %s" % [max_points, ret_points.size()])
	return ret_points


## Radius for the point at `idx`: its own entry in `point_radii` when present,
## else the uniform `fallback`.
static func _radius_at(point_radii: Array[float], idx: int, fallback: float) -> float:
	return point_radii[idx] if idx < point_radii.size() else fallback
#endregion

#region Private helpers
## All in-bounds, passable grid cells adjacent (L∞ = 1) to any cell in
## `a_structure`'s registered footprint, excluding the footprint cells themselves.
## De-duplicated and unordered. Shared by passable_cells_adjacent_to (which
## shuffles the result) and nearest_footprint_adjacent_cell (which picks the one
## closest to a point).
static func _passable_footprint_neighbors(a_structure: Commandable, a_map: Map) -> Array[Vector2i]:
	if a_structure == null or a_map == null:
		return []

	var footprint: Array = a_map.structure_cell_map.get(a_structure, [])
	# `seen` excludes footprint cells and de-duplicates neighbors reachable from
	# more than one footprint cell.
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
				seen[neighbor] = true
				if not a_map.grid_coordinates_in_bounds(neighbor):
					continue
				if not a_map.terrain_grid.is_passable(neighbor):
					continue
				result.append(neighbor)
	return result

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
#endregion
