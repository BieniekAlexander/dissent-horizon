class_name SpatialIndex
extends RefCounted

## THE PIECES' HURTBOXES ON A GRID, as the last tick left them — what the decide pass reads
## instead of the physics server. gdd/systems/commands/the-simulation-step.md §The spatial index.
##
## Brought up to date by the stepper at the start of every tick, before anything decides, so it
## is the same world the decide pass reads everywhere else; nothing writes it until the next
## update, which is what lets decide run on threads later. Only pieces that moved are measured
## again. Each entry is a piece's footprint (Hull),
## its Hurtbox's collision layers (side bits included) and the Hurtbox's vertical span — what a
## physics query on a TARGETABLE mask hits. C&C Generals' PartitionManager is the same idea.

## World units per grid cell: a few cells across a typical aggro range (5–10), so a query
## reads a handful of cells rather than every piece.
const CELL_SIZE: float = 8.0

## The index serving the decide pass while it runs, else null. SU.entities_within reads
## through it when it is set. Static because the readers — scans deep in commands — have no
## path to their stepper; one decide pass runs at a time.
static var reading: SpatialIndex = null


## Whether a query on `collision_mask` asks only about layers a Hurtbox carries — the ones this
## index holds. A mask on the root body's layers (STEALTH, MOVEMENT_OBSTRUCTION) is not.
static func answers(collision_mask: int) -> bool:
	var hurtbox_layers: int = (
		CollisionLayers.TARGETABLE_ANY
		| CollisionLayers.all_side_bits(CollisionLayers.TARGETABLE_ANY)
		| CollisionLayers.Mask.STRUCTURE_BLOCKER
		| CollisionLayers.Mask.LIBERATABLE
	)
	return collision_mask & ~hurtbox_layers == 0


## Cell -> Array of entries. An entry is [entity, hull, layers, y_min, y_max, hurtbox rid,
## cells, hurtbox transform, shape key, stamp, instance id]; queries read the first six and
## sort by serial, so the order entries sit in a cell does not matter.
var _cells: Dictionary = {}
## Instance id -> entry, kept between ticks so a piece that has not moved is not measured again.
var _entries: Dictionary = {}
## Bumped by every update; an entry not stamped with the latest has left play.
var _stamp: int = 0
## Instance ids of tracked pieces whose Hurtbox may have changed since the last update: moved,
## entered or left the tree, or had its layers written (Entity.mark_spatial_dirty).
var _dirty: Dictionary = {}
## Whether the first full scan has run; after it, update_dirty touches only the dirty.
var _has_scanned: bool = false

## Rebuild a fresh index every update and assert the incremental one matches it, entry for
## entry: the check that every change to a Hurtbox marks its piece. For the determinism probe
## (`--verify-index`) and tests; far too slow to leave on.
static var is_verifying: bool = false


## Keep `a_entity` up to date in this index from now on: its transform changes, tree changes
## and layer writes mark it dirty (Entity.mark_spatial_dirty). Called as it enters play.
func track(a_entity: Entity) -> void:
	a_entity.track_in_spatial_index(self)
	mark(a_entity)


func mark(a_entity: Entity) -> void:
	_dirty[a_entity.get_instance_id()] = true


## Bring the index up to date from the dirty marks alone — the pieces that moved, arrived, left
## or changed layers since the last update — after one full scan of `a_entities` (every tracked
## piece in play) the first time.
func update_dirty(a_entities: Array) -> void:
	if not _has_scanned:
		_has_scanned = true
		_dirty.clear()
		update(a_entities)
	else:
		_stamp += 1
		for id: int in _dirty.keys():
			var found: Object = instance_from_id(id)
			var entity := found as Entity
			if entity == null or not _refresh(entity):
				var entry: Variant = _entries.get(id)
				if entry != null:
					_unfile(entry)
		_dirty.clear()
	if is_verifying:
		_verify(a_entities)


## Index every piece in `a_entities` that has a Hurtbox in the tree, from scratch.
func rebuild(a_entities: Array) -> void:
	_cells.clear()
	_entries.clear()
	update(a_entities)


## Bring the index up to date with `a_entities`, the pieces in play as the tick starts. A piece
## whose Hurtbox transform and shape are exactly as last indexed keeps its entry — only its
## layers are re-read — so the cost is the pieces that moved, not every piece: half of them are
## buildings. One that has left play (freed, off the tree) is dropped.
func update(a_entities: Array) -> void:
	_stamp += 1
	for item: Variant in a_entities:
		if is_instance_valid(item):
			_refresh(item as Entity)
	for id: int in _entries.keys():
		if int(_entries[id][9]) != _stamp:
			_unfile(_entries[id])


## Bring `a_entity`'s entry up to date and stamp it; false — and no entry made — when it has no
## Hurtbox in the tree to index.
func _refresh(a_entity: Entity) -> bool:
	if not a_entity.is_inside_tree() or a_entity.hurtbox == null:
		return false
	var shape_node := a_entity.hurtbox.get_node_or_null("HurtboxShape") as CollisionShape3D
	if shape_node == null or shape_node.shape == null or not shape_node.is_inside_tree():
		return false
	var xform: Transform3D = shape_node.global_transform
	var key: Vector3 = _shape_key(shape_node.shape)
	var entry: Variant = _entries.get(a_entity.get_instance_id())
	if entry != null and entry[7] == xform and entry[8] == key:
		entry[2] = a_entity.hurtbox.collision_layer
		entry[9] = _stamp
		return true
	if entry != null:
		_unfile(entry)
	_file(_measure(a_entity, shape_node, xform, key))
	return true


## Assert this index holds exactly what a fresh scan of `a_entities` would: the same pieces,
## each in the same cells with the same layers and span.
func _verify(a_entities: Array) -> void:
	var fresh := SpatialIndex.new()
	fresh.update(a_entities)
	var mine: Dictionary = _signatures()
	var theirs: Dictionary = fresh._signatures()
	for id: int in theirs:
		assert(mine.get(id) == theirs[id], "SpatialIndex stale for %s" % instance_from_id(id))
	for id: int in mine:
		assert(theirs.has(id), "SpatialIndex holds %s, gone from play" % instance_from_id(id))


func _signatures() -> Dictionary:
	var out: Dictionary = {}
	for id: int in _entries:
		var entry: Array = _entries[id]
		out[id] = [entry[6], entry[2], entry[3], entry[4]]
	return out


## A fresh entry for `a_entity`, whose Hurtbox shape is `a_shape_node` at `a_xform`.
func _measure(
	a_entity: Entity, a_shape_node: CollisionShape3D, a_xform: Transform3D, a_key: Vector3
) -> Array:
	var half: float = Entity._half_height_of(a_shape_node.shape) * a_xform.basis.y.length()
	var y: float = a_xform.origin.y
	var hull: Hull = a_entity.hull()
	return [
		a_entity,
		hull,
		a_entity.hurtbox.collision_layer,
		y - half,
		y + half,
		a_entity.hurtbox.get_rid(),
		_cells_around(hull.center, hull.extent()),
		a_xform,
		a_key,
		_stamp,
		a_entity.get_instance_id()
	]


func _file(a_entry: Array) -> void:
	_entries[int(a_entry[10])] = a_entry
	for cell: Vector2i in a_entry[6]:
		if not _cells.has(cell):
			_cells[cell] = []
		(_cells[cell] as Array).append(a_entry)


## Take `a_entry` out of its cells and the index. Touches nothing on its entity, which may be
## freed.
func _unfile(a_entry: Array) -> void:
	for cell: Vector2i in a_entry[6]:
		var filed: Array = _cells.get(cell, [])
		filed.erase(a_entry)
		if filed.is_empty():
			_cells.erase(cell)
	_entries.erase(int(a_entry[10]))


## What decides a Hurtbox's footprint and span besides its transform: its dimensions, so a
## shape resized in place (live tuning) is measured again.
static func _shape_key(a_shape: Shape3D) -> Vector3:
	if a_shape is BoxShape3D:
		return (a_shape as BoxShape3D).size
	if a_shape is CylinderShape3D:
		return Vector3((a_shape as CylinderShape3D).radius, (a_shape as CylinderShape3D).height, 1)
	if a_shape is CapsuleShape3D:
		return Vector3((a_shape as CapsuleShape3D).radius, (a_shape as CapsuleShape3D).height, 2)
	if a_shape is SphereShape3D:
		return Vector3((a_shape as SphereShape3D).radius, 0, 3)
	return Vector3.ZERO


## The pieces whose Hurtbox carries a layer in `collision_mask`, whose span overlaps `shape`
## standing upright at `origin`, and whose footprint lies within the shape's radius of
## `from` — SU.entities_within's answer, in serial order and uncapped. `exclude` holds RIDs or
## entities to skip.
func entities_within(
	from: Hull, shape: Shape3D, origin: Vector3, collision_mask: int, exclude: Array = []
) -> Array[Entity]:
	var found: Array[Entity] = []
	var radius: float = RangeShapes.radius_of(shape)
	if radius < 0.0:
		return found
	var half_height: float = (
		(shape as CylinderShape3D).height * 0.5 if shape is CylinderShape3D else radius
	)
	var seen: Dictionary = {}
	var matches: Array = []
	for cell: Vector2i in _cells_around(from.center, radius + from.extent()):
		for entry: Array in _cells.get(cell, []):
			var entity: Entity = entry[0]
			if seen.has(entity):
				continue
			seen[entity] = true
			if int(entry[2]) & collision_mask == 0:
				continue
			if float(entry[4]) < origin.y - half_height or float(entry[3]) > origin.y + half_height:
				continue
			if exclude.has(entry[5]) or exclude.has(entity):
				continue
			if Hull.gap(from, entry[1]) > radius:
				continue
			matches.append(entry)
	matches.sort_custom(
		func(a: Array, b: Array) -> bool:
			return (a[0] as Entity).spawn_serial < (b[0] as Entity).spawn_serial
	)
	for entry: Array in matches:
		found.append(entry[0])
	return found


## The pieces whose Hurtbox carries a layer in `collision_mask` and touches `shape` (a cylinder
## or sphere) standing upright at `origin` — SU.entities_touched_by's answer, in serial order.
## A Hurtbox is an upright prism (cylinder or yaw-turned box on its base), so a cylinder touches
## it when its footprint comes within the radius and the vertical spans overlap, and a sphere
## when the horizontal and vertical gaps together come within it.
func entities_touched_by(
	shape: Shape3D, origin: Vector3, collision_mask: int, exclude: Array = []
) -> Array[Entity]:
	var found: Array[Entity] = []
	var radius: float = RangeShapes.radius_of(shape)
	if radius < 0.0:
		return found
	var is_sphere: bool = shape is SphereShape3D
	var half_height: float = (
		(shape as CylinderShape3D).height * 0.5 if shape is CylinderShape3D else radius
	)
	var at := Vector2(origin.x, origin.z)
	var seen: Dictionary = {}
	var matches: Array = []
	for cell: Vector2i in _cells_around(at, radius):
		for entry: Array in _cells.get(cell, []):
			var entity: Entity = entry[0]
			if seen.has(entity):
				continue
			seen[entity] = true
			if int(entry[2]) & collision_mask == 0:
				continue
			if exclude.has(entry[5]) or exclude.has(entity):
				continue
			var gap_xz: float = (entry[1] as Hull).distance_to_point(at)
			var gap_y: float = maxf(
				maxf(float(entry[3]) - origin.y, origin.y - float(entry[4])), 0.0
			)
			var touches: bool = (
				gap_xz * gap_xz + gap_y * gap_y <= radius * radius
				if is_sphere
				else gap_xz <= radius and gap_y <= half_height
			)
			if touches:
				matches.append(entry)
	matches.sort_custom(
		func(a: Array, b: Array) -> bool:
			return (a[0] as Entity).spawn_serial < (b[0] as Entity).spawn_serial
	)
	for entry: Array in matches:
		found.append(entry[0])
	return found


## Whether the segment `a_from` -> `a_to` passes through the Hurtbox of a piece on
## STRUCTURE_BLOCKER other than `a_ends` — the obstruction half of Attack's line of fire. A
## segment that starts inside a blocker does not count it, as a physics ray does not.
func segment_hits_blocker(a_from: Vector3, a_to: Vector3, a_ends: Array) -> bool:
	var from_xz := Vector2(a_from.x, a_from.z)
	var delta_xz := Vector2(a_to.x - a_from.x, a_to.z - a_from.z)
	var middle: Vector2 = from_xz + delta_xz * 0.5
	for cell: Vector2i in _cells_around(middle, delta_xz.length() * 0.5):
		for entry: Array in _cells.get(cell, []):
			if int(entry[2]) & CollisionLayers.Mask.STRUCTURE_BLOCKER == 0:
				continue
			if a_ends.has(entry[0]):
				continue
			var span: Vector2 = (entry[1] as Hull).segment_span(from_xz, delta_xz)
			if span.x > span.y:
				continue
			var y_enter: float = lerpf(a_from.y, a_to.y, span.x)
			var y_exit: float = lerpf(a_from.y, a_to.y, span.y)
			var low: float = float(entry[3])
			var high: float = float(entry[4])
			if maxf(y_enter, y_exit) < low or minf(y_enter, y_exit) > high:
				continue
			if span.x == 0.0 and y_enter >= low and y_enter <= high:
				continue
			return true
	return false


## Whether any piece hostile to `a_watcher` has a footprint within `a_radius` of the watcher's,
## at any height and whether or not it can be seen — everything an idle scan could ever find
## a target among, and more. What wakes a sleeping armed piece.
func has_hostile_near(a_watcher: Entity, a_radius: float) -> bool:
	var hostile: int = CollisionLayers.hostile_mask(
		CollisionLayers.TARGETABLE_ANY, a_watcher.allied_commander_ids()
	)
	var from: Hull = a_watcher.hull()
	for cell: Vector2i in _cells_around(from.center, a_radius + from.extent()):
		for entry: Array in _cells.get(cell, []):
			if int(entry[2]) & hostile != 0 and Hull.gap(from, entry[1]) <= a_radius:
				return true
	return false


## The cells a disc of `a_radius` around `a_center` touches.
static func _cells_around(a_center: Vector2, a_radius: float) -> Array[Vector2i]:
	var low: Vector2i = Vector2i(
		floori((a_center.x - a_radius) / CELL_SIZE), floori((a_center.y - a_radius) / CELL_SIZE)
	)
	var high: Vector2i = Vector2i(
		floori((a_center.x + a_radius) / CELL_SIZE), floori((a_center.y + a_radius) / CELL_SIZE)
	)
	var cells: Array[Vector2i] = []
	for x: int in range(low.x, high.x + 1):
		for z: int in range(low.y, high.y + 1):
			cells.append(Vector2i(x, z))
	return cells
