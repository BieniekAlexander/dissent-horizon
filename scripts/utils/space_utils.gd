# Utilities that deal with the relationships of things in space
# I'm hoping this will make my distance calculations more expressive,
# e.g. checking if a unit is adjacent to a structure, which sits on a set of hex cells
class_name SU

#region Properties
static var rng = RandomNumberGenerator.new()

## How far (in XZ world units) a candidate point may drift from the navmesh
## closest-point snap before it is considered off-navmesh.  Half a cell width
## (CELL_SIZE = 1.0) keeps points well inside valid navmesh quads.
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
		(
			world_3d
			. direct_space_state
			. intersect_shape(params, max_results)
			. map(func(d: Dictionary) -> Entity: return Entity.entity_from_collider(d["collider"]))
			. filter(func(e: Entity) -> bool: return e != null)
		)
	)
	return result


static func get_nearby_entities(
	world_3d: World3D, position: Vector3, radius: float, collision_mask: int, max_results: int
) -> Array:
	var shape := SphereShape3D.new()
	shape.radius = radius
	return query_shape_for_entities(
		world_3d, shape, Transform3D(Basis(), position), collision_mask, [], max_results
	)


## The gap between two pieces' footprints (Entity.hull), or 0.0 when they touch. EVERY
## piece-to-piece range is this gap against a radius, from whichever end it is asked, so no
## range favours the bigger body. Why: gdd/systems/combat/range-buckets.md §Ranges are
## measured between hulls.
static func hull_gap(a: Entity, b: Entity) -> float:
	return Hull.gap(a.hull(), b.hull())


## Entities on `collision_mask` whose footprint lies within `radius` of `from`'s — the one
## query behind aggro, detection and the other "who is within R of me" ranges. `shape` is the
## range volume, placed upright at `origin`: the physics query grows it by `from`'s own
## extent as a broad phase (keeping the shape's height, so a short volume still ignores what
## flies over it), and the exact footprint gap then decides. `exclude` is a list of
## RIDs/Objects to skip.
static func entities_within(
	world_3d: World3D,
	from: Hull,
	shape: Shape3D,
	origin: Vector3,
	collision_mask: int,
	exclude: Array = [],
	max_results: int = 32
) -> Array[Entity]:
	var radius: float = RangeShapes.radius_of(shape)
	if radius < 0.0:
		return []
	var broad: Shape3D = _grow_shape_radius(shape, from.extent())
	var found: Array[Entity] = query_shape_for_entities(
		world_3d, broad, Transform3D(Basis.IDENTITY, origin), collision_mask, exclude, max_results
	)
	return found.filter(func(e: Entity) -> bool: return Hull.gap(from, e.hull()) <= radius)


static func linf_distance(pos1: Vector2i, pos2: Vector2i) -> int:
	var diff = (pos1 - pos2).abs()
	return max(diff.x, diff.y)


## Whether `attacker` can reach `target` with `weapon` from where it stands: the weapon has
## a range for the layer the target is on, and the gap between the two footprints is within
## that reach plus `reach_bonus` (a garrison's). A bunker's occupants fire from the HOST, so
## Garrison passes the host as `attacker`. A weapon measuring from its wielder's orbit instead
## stands its range shape at the orbit's centre and asks whether it overlaps the target's
## hurtbox (Weapon.RangeOrigin.ORBIT).
static func is_in_attack_range(
	weapon: Weapon, attacker: Entity, target: Entity, reach_bonus: float = 0.0
) -> bool:
	if weapon == null or not is_instance_valid(target) or not target.is_inside_tree():
		return false
	# NO REACH AGAINST THIS KIND OF TARGET IS NOT IN RANGE. get_range_for_target returns null
	# when the weapon carries no range shape for the side the target is on — a ground-only
	# weapon asked about an air target, or an AA gun asked about one that has landed — and
	# that null is an answer, not an oversight. It is reachable even though
	# Loadout.weapon_for_target only hands back a weapon whose can_target() passed: can_target
	# reads the Hurtbox's LAYER, latched at the end of a tick, while get_range_for_target
	# reads LIVE altitude, and for the one tick a piece crosses Aerial.AIR_TARGET_ALTITUDE the
	# two disagree.
	var range_node: CollisionShape3D = weapon.get_range_for_target(target)
	if range_node == null or range_node.shape == null:
		return false
	if weapon.target_mask & target.targetable_layers() == 0:
		return false
	var orbit_origin: Variant = weapon.orbit_origin(attacker)
	if orbit_origin is Vector3:
		return shape_touches_hurtbox(
			attacker.get_world_3d(),
			_grow_shape_radius(range_node.shape, reach_bonus),
			orbit_origin,
			target
		)
	var reach: float = RangeShapes.radius_of(range_node.shape)
	return reach >= 0.0 and hull_gap(attacker, target) <= reach + reach_bonus


## How many hurtboxes one range-shape query may report. Generous, because a per-target check
## reads its answer from this list, and a crowd that filled it would hide the target.
const RANGE_SHAPE_MAX_RESULTS: int = 128


## The pieces on `collision_mask` whose HURTBOX the range shape `shape`, standing upright at
## `origin`, overlaps — measured by the physics server, not by footprint gap. What a weapon
## measuring from its wielder's orbit (Weapon.RangeOrigin.ORBIT) reaches.
static func entities_touched_by(
	world_3d: World3D, shape: Shape3D, origin: Vector3, collision_mask: int, exclude: Array = []
) -> Array[Entity]:
	if world_3d == null or shape == null:
		return []
	return query_shape_for_entities(
		world_3d,
		shape,
		Transform3D(Basis.IDENTITY, origin),
		collision_mask,
		exclude,
		RANGE_SHAPE_MAX_RESULTS
	)


## Whether the range shape `shape`, standing at `origin`, overlaps `target`'s hurtbox.
static func shape_touches_hurtbox(
	world_3d: World3D, shape: Shape3D, origin: Vector3, target: Entity
) -> bool:
	if target.hurtbox == null:
		return false
	return entities_touched_by(world_3d, shape, origin, target.hurtbox.collision_layer).has(target)


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


static func unit_is_close_to_target(
	unit: Actor, target: Variant, distance_squared: float = .001
) -> bool:
	# Group-based, not type-based: a structure may be an Entity that is NOT a Actor
	# (e.g. ShelterStructure / ExtractionSite), and it still wants footprint-adjacency proximity
	# rather than the strict touch-the-target-body check used for mobile units.
	if target is Entity and target.is_in_group("fixture"):
		return SU.unit_is_close_to_structure(unit, target, distance_squared)
	elif target is Entity:
		return SU.unit_is_close_to_unit(unit, target, distance_squared)
	elif target is Vector2:
		return SU.unit_is_close_to_position(unit, target, distance_squared)
	else:
		push_error("unsuported distance target type")
		return false


static func unit_is_close_to_position(
	unit: Actor, position: Vector2, _distance_squared: float = .001
) -> bool:
	# The navigation agent stops at the destination rather than overshooting, so
	# arrival is just a position-equality check — no collision radius needed.
	return unit.xz_position.is_equal_approx(position)


static func unit_is_close_to_structure(
	unit: Actor, structure: Entity, _distance_squared: float = .001
) -> bool:
	# A unit counts as close to a structure when its grid cell lies within the
	# structure's footprint or is immediately adjacent to it (see
	# unit_is_close_to_footprint). Measuring against the whole footprint makes
	# proximity scale with the building's size: otherwise a builder would have to
	# stand *on* a cell the structure occupies, impossible for anything > 1x1.
	var placement_map: Map = structure.map
	if placement_map == null:
		return (
			linf_distance(VU.in_xz(unit.global_position), VU.in_xz(structure.global_position)) <= 1
		)
	var footprint: Array = structure_footprint(placement_map, structure)
	if footprint.is_empty():
		# Footprint not registered yet — fall back to the structure's origin cell.
		footprint = [placement_map.world_to_grid(VU.in_xz(structure.global_position))]
	return unit_is_close_to_footprint(unit, placement_map, footprint)


## The grid cells to measure build/repair proximity against for a structure.
## The structure's own registered footprint; an Extractor not yet registered but already
## bound to its ExtractionSite reports the site's footprint, which is the one it will take.
## Empty if neither is registered yet.
static func structure_footprint(map: Map, structure: Entity) -> Array:
	if map == null or structure == null:
		return []
	var own: Array = map.structure_cell_map.get(structure, [])
	if not own.is_empty():
		return own
	var extractor: Extractor = Extractor.of(structure)
	if extractor != null and extractor.extraction_site != null:
		return map.structure_cell_map.get(extractor.extraction_site, [])
	return []


## Every OTHER entity registered on a grid cell that shares an EDGE with `structure`'s
## footprint — the buildings it physically touches. De-duplicated; never contains
## `structure` itself; empty for anything not registered on the grid.
##
## DIAGONALS ARE EXCLUDED, and that is the whole difference from
## `_passable_footprint_neighbors`. Two buildings meeting at a corner share no wall, and
## "adjacent" in the game's sense — a Compound working the buildings around it — means they
## do. The other helper asks the opposite question (where can a unit STAND next to this?)
## and wants the diagonals, so the two cannot be one.
static func edge_adjacent_structures(map: Map, structure: Entity) -> Array[Entity]:
	var out: Array[Entity] = []
	if map == null or structure == null:
		return out
	var footprint: Array = structure_footprint(map, structure)
	if footprint.is_empty():
		return out
	var own: Dictionary = {}
	for cell: Vector2i in footprint:
		own[cell] = true
	var seen: Dictionary = {}
	for cell: Vector2i in footprint:
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor: Vector2i = cell + step
			if own.has(neighbor) or not map.grid_coordinates_in_bounds(neighbor):
				continue
			var occupant := map.cell_grid[neighbor.x][neighbor.y] as Entity
			if occupant == null or occupant == structure or seen.has(occupant):
				continue
			seen[occupant] = true
			out.append(occupant)
	return out


## True when a_unit's grid cell lies within (L∞ ≤ 1 of) any cell in `footprint` —
## i.e. on the footprint or immediately adjacent. The shared "close enough to
## build / repair / work on" predicate. Build measures against the would-be
## footprint (Map.footprint_cells of the clicked spot) and Repair against the
## structure's registered footprint; because add_structure registers exactly the
## cells footprint_cells returns, the two checks always agree.
##
## A unit wider than a cell is ALSO close once it is within its nav size class's standoff
## of the footprint (see _within_class_standoff): its class navmesh is eroded back from
## every building edge by NavAgentClass.radius, which for MEDIUM (0.95) leaves almost none
## of an adjacent cell reachable — so the grid test alone is one such a unit can never pass,
## and a Stock Truck parked at its Compound stood there forever, loaded.
static func unit_is_close_to_footprint(unit: Actor, map: Map, footprint: Array) -> bool:
	if map == null or footprint.is_empty():
		return false
	var unit_cell: Vector2i = map.world_to_grid(VU.in_xz(unit.global_position))
	for cell: Vector2i in footprint:
		if linf_distance(unit_cell, cell) <= 1.:
			return true
	return _within_class_standoff(unit, map, footprint)


## How far past its class navmesh's edge a unit may come to rest and still count as having
## got as close as navigation allows: the agent halts short of its mesh's nearest point
## (measured ~0.5), and the inset is a chamfer rather than a true offset, so corners sit
## further out still. One cell covers both without reaching a second cell's worth of ground.
const CLASS_STANDOFF_SLACK: float = Map.CELL_SIZE


## How far a unit of NavAgentClass.Size `nav_class` may be left from a point its navmesh
## steers it toward and still be as close as that class gets — its erosion plus the slack.
static func class_standoff_reach(nav_class: int) -> float:
	return NavAgentClass.radius(nav_class, Map.CELL_SIZE) + CLASS_STANDOFF_SLACK


## Whether `unit` is within the closest distance its navigation size class can bring it to
## `footprint` — NavAgentClass.radius (the erosion of its class mesh) plus
## CLASS_STANDOFF_SLACK — measured from the unit's XZ position to the nearest footprint
## cell's square. False for a unit with no Movement, which never pathed there anyway.
static func _within_class_standoff(unit: Actor, map: Map, footprint: Array) -> bool:
	if unit.movement == null:
		return false
	var reach: float = class_standoff_reach(unit.movement.nav_agent_class)
	var here: Vector2 = VU.in_xz(unit.global_position)
	var half: float = Map.CELL_SIZE * 0.5
	for cell: Vector2i in footprint:
		var offset: Vector2 = (here - VU.in_xz(map.grid_to_world(cell))).abs()
		var outside: Vector2 = (offset - Vector2(half, half)).max(Vector2.ZERO)
		if outside.length() <= reach:
			return true
	return false


## Whether `target` lies within an interaction's authored reach `shape` (e.g. a Cylinder)
## of `unit`: the footprint gap within the shape's radius, with the shape's height kept by
## the broad phase (see entities_within). False when the shape or target is missing.
static func unit_shape_overlaps_target(unit: Actor, target: Entity, shape: Shape3D) -> bool:
	if shape == null or not is_instance_valid(target):
		return false
	return (
		target
		in entities_within(
			unit.get_world_3d(),
			unit.hull(),
			shape,
			unit.global_position,
			CollisionLayers.TARGETABLE_ANY,
			[unit]
		)
	)


## Engagement proximity: the two footprints touch, within a slack whose SQUARE is
## `distance_squared`.
static func unit_is_close_to_unit(
	unit: Actor, an_entity: Entity, distance_squared: float = .001
) -> bool:
	var gap: float = hull_gap(unit, an_entity)
	return gap * gap < distance_squared


## Return all unique grid cells that are directly adjacent (L∞-distance 1) to
## any cell in `a_structure`'s footprint, are in-bounds, and are currently
## passable (not occupied by another structure, not too steep).  The returned
## list is shuffled so callers can pop_front() to assign distinct destinations
## without bias.
##
## ENTITY, not Actor — a structure need not be a Actor (an ExtractionSite, a
## Shelter and a Rock are plain Entities carrying a Structure component), and every other
## member of this family already says Entity: `_passable_footprint_neighbors`, which does
## all the work, `nearest_footprint_adjacent_cell`, and `unit_is_close_to_structure`. This
## one was the straggler.
static func passable_cells_adjacent_to(structure: Entity, map: Map) -> Array[Vector2i]:
	var result: Array[Vector2i] = _passable_footprint_neighbors(structure, map)
	AU.shuffle(result, rng)
	return result


## The nearest of `candidates` (Commandables) to `from`, by XZ distance, or null when
## `candidates` is empty. A small generic query — TaskShelter's nearest-Compound-with-room
## and Commander.projected_dominion_rate's nearest-Compound-to-a-Shelter are both this,
## asked from a different point, and neither wants its own copy of "walk a list, keep the
## closest".
static func nearest_of(candidates: Array, from: Entity) -> Actor:
	var best: Actor = null
	var best_distance: float = 0.0
	for candidate: Actor in candidates:
		var distance: float = from.xz_position.distance_to(candidate.xz_position)
		if best == null or distance < best_distance:
			best = candidate
			best_distance = distance
	return best


## Return the grid cell adjacent to `a_structure`'s footprint — in-bounds, passable, and
## EDGE-adjacent, never a diagonal corner — whose world-space centre is closest to `dest`, or
## Vector2i(-1, -1) when none exists. A navigation destination, so reachability rules out the
## corners (agent-size-classes.md §Reaching a building).
##
## `nav_class`, when given, is the walker's NavAgentClass.Size — see footprint_approach_cells.
static func nearest_footprint_adjacent_cell(
	dest: Vector3, structure: Entity, map: Map, nav_class: int = NO_NAV_CLASS
) -> Vector2i:
	var cells: Array[Vector2i] = footprint_approach_cells(dest, structure, map, nav_class)
	return cells.front() if not cells.is_empty() else Vector2i(-1, -1)


## Every passable cell EDGE-adjacent to `structure`'s footprint, nearest to `dest` first.
##
## `nav_class`, when given, is the walker's NavAgentClass.Size: cells that class cannot stand
## on (TerrainGrid.is_navigable_for — the gate its navmesh is baked from) are dropped, so a
## truck is not sent into a one-cell gap between two buildings. Falls back to every passable
## candidate when the class fits none. Standable is not REACHABLE — a pocket walled in by
## other buildings passes this test — which is why CommandReceiver checks the ranked list
## against a real path before committing to one.
static func footprint_approach_cells(
	dest: Vector3, structure: Entity, map: Map, nav_class: int = NO_NAV_CLASS
) -> Array[Vector2i]:
	var footprint: Array = structure_footprint(map, structure)
	var candidates: Array[Vector2i] = []
	for cell: Vector2i in _passable_footprint_neighbors(structure, map):
		if _edge_adjacent_to_any(cell, footprint):
			candidates.append(cell)
	if nav_class != NO_NAV_CLASS:
		var rings: int = NavAgentClass.erosion_rings(nav_class, Map.CELL_SIZE)
		var admit_k: int = NavAgentClass.required_clearance(nav_class, Map.CELL_SIZE)
		var standable: Array[Vector2i] = []
		for cell: Vector2i in candidates:
			if map.terrain_grid.is_navigable_for(cell, rings, admit_k):
				standable.append(cell)
		if not standable.is_empty():
			candidates = standable
	candidates.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return (
				map.grid_to_world(a).distance_squared_to(dest)
				< map.grid_to_world(b).distance_squared_to(dest)
			)
	)
	return candidates


## `nearest_footprint_adjacent_cell`'s "no walker class" — NavAgentClass.Size starts at 1.
const NO_NAV_CLASS: int = 0


## Whether `cell` shares a grid EDGE (not merely a corner) with at least one cell in
## `footprint` — Manhattan distance exactly 1, i.e. one axis differs by 1 AND THE OTHER BY
## 0. (`diff.x == 1 or diff.y == 1` alone is not enough: (1, 2) satisfies that but is two
## cells away on the other axis, not adjacent at all.)
static func _edge_adjacent_to_any(cell: Vector2i, footprint: Array) -> bool:
	for f: Vector2i in footprint:
		var diff: Vector2i = (cell - (f as Vector2i)).abs()
		if diff.x + diff.y == 1:
			return true
	return false


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
##
## The scatter grows outward from points it has already placed, so it needs one free
## seed. When `center` itself is taken — the usual case for a spawn anchored on a
## structure, whose footprint has no navmesh — the seed is the first free point on
## rings walked outward from it (see _seed_off_center).
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
	# Radius each of ret_points was placed at: an accepted point has no body yet, so the
	# physics probe cannot see it, and a candidate is checked against these instead.
	var ret_radii: Array[float] = []

	# A sphere sized per candidate; radius is reset before each free-space probe.
	var probe_shape := SphereShape3D.new()

	# Seed with center if it is free, else with the nearest free point around it.
	var seed_radius: float = _radius_at(point_radii, 0, point_radius)
	probe_shape.radius = seed_radius
	var seed: Vector2 = (
		center
		if _is_free_on_nav(map, center, probe_shape, world_3d, collision_mask)
		else _seed_off_center(
			map, center, probe_shape, world_3d, collision_mask, region_radius, sample_count
		)
	)
	if seed != NO_POINT:
		ret_points.append(seed)
		ret_radii.append(seed_radius)
		about_points.append(seed)
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

			if (
				_clears_points(new_point, new_radius, ret_points, ret_radii)
				and _is_free_on_nav(map, new_point, probe_shape, world_3d, collision_mask)
			):
				about_points.insert(0, new_point)
				about_radii.insert(0, new_radius)
				ret_points.append(new_point)
				ret_radii.append(new_radius)

				if ret_points.size() == max_points:
					return ret_points

				candidate_accepted = true
				break

		if not candidate_accepted:
			about_points.remove_at(0)
			about_radii.remove_at(0)

	push_error(
		"Not enough points collected - requested %s, got %s" % [max_points, ret_points.size()]
	)
	return ret_points


## get_nonoverlapping_points' "no seed was found".
const NO_POINT: Vector2 = Vector2(INF, INF)

## The ring spacing _seed_off_center falls back to for a body with no radius, so the walk
## still advances: half a cell, the same resolution _NAV_SNAP_TOLERANCE accepts.
const MIN_SEED_RING_STEP: float = Map.CELL_SIZE * 0.5


## The first free point on rings walked outward from a taken `center`, one probe body
## (`probe_shape.radius`) apart, out to `region_radius` — or to the map's own size, past
## which every candidate is off the navmesh anyway. Each ring is sampled at
## `sample_count` random angles. NO_POINT when no ring has room.
static func _seed_off_center(
	map: Map,
	center: Vector2,
	probe_shape: SphereShape3D,
	world_3d: World3D,
	collision_mask: int,
	region_radius: float,
	sample_count: int,
) -> Vector2:
	var step: float = maxf(probe_shape.radius, MIN_SEED_RING_STEP)
	var columns: int = map.cell_grid.size()
	var rows: int = map.cell_grid[0].size() if columns > 0 else 0
	var map_span: float = Vector2(columns, rows).length() * Map.CELL_SIZE
	var search_radius: float = minf(region_radius, map_span)
	var ring: float = step
	while ring < search_radius:
		for i in range(sample_count):
			var angle: float = 2.0 * PI * rng.randf()
			var candidate: Vector2 = center + ring * Vector2(sin(angle), cos(angle))
			if _is_free_on_nav(map, candidate, probe_shape, world_3d, collision_mask):
				return candidate
		ring += step
	return NO_POINT


## Whether a body of `radius` at `point` overlaps none of `points`, each of the radius at
## the same index of `radii`.
static func _clears_points(
	point: Vector2, radius: float, points: Array[Vector2], radii: Array[float]
) -> bool:
	for i: int in points.size():
		if point.distance_to(points[i]) < radius + radii[i]:
			return false
	return true


## Whether `point_xz` is on the navmesh and `probe_shape`, stood there, overlaps nothing
## on `collision_mask`.
static func _is_free_on_nav(
	map: Map, point_xz: Vector2, probe_shape: Shape3D, world_3d: World3D, collision_mask: int
) -> bool:
	var ground_pos: Vector3 = _project_to_nav_surface(map, point_xz)
	return (
		ground_pos != Vector3.INF
		and _shape_has_space(
			Transform3D(Basis(), ground_pos), probe_shape, world_3d, collision_mask
		)
	)


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
static func _passable_footprint_neighbors(structure: Entity, map: Map) -> Array[Vector2i]:
	if structure == null or map == null:
		return []

	# structure_footprint, NOT structure_cell_map directly, so this and
	# unit_is_close_to_structure (the matching RANGE check) resolve a footprint the same way.
	var footprint: Array = structure_footprint(map, structure)
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
				if not map.grid_coordinates_in_bounds(neighbor):
					continue
				if not map.terrain_grid.is_passable(neighbor):
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
	shape_transform: Transform3D, shape: Shape3D, world_3d: World3D, collision_mask: int
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
