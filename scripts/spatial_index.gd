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
		if not is_instance_valid(item):
			continue
		var entity: Entity = item
		if not entity.is_inside_tree() or entity.hurtbox == null:
			continue
		var shape_node := entity.hurtbox.get_node_or_null("HurtboxShape") as CollisionShape3D
		if shape_node == null or shape_node.shape == null or not shape_node.is_inside_tree():
			continue
		var xform: Transform3D = shape_node.global_transform
		var key: Vector3 = _shape_key(shape_node.shape)
		var entry: Variant = _entries.get(entity.get_instance_id())
		if entry != null and entry[7] == xform and entry[8] == key:
			entry[2] = entity.hurtbox.collision_layer
			entry[9] = _stamp
			continue
		if entry != null:
			_unfile(entry)
		_file(_measure(entity, shape_node, xform, key))
	for id: int in _entries.keys():
		if int(_entries[id][9]) != _stamp:
			_unfile(_entries[id])


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
