class_name SpatialIndex
extends RefCounted

## THE PIECES' HURTBOXES ON A GRID, as the last tick left them — what the decide pass reads
## instead of the physics server. gdd/systems/commands/the-simulation-step.md §The spatial index.
##
## Rebuilt by the stepper at the start of every tick, before anything decides, so it is the
## same world the decide pass reads everywhere else; nothing writes it until the next rebuild,
## which is what lets decide run on threads later. Each entry is a piece's footprint (Hull),
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


## Cell -> Array of entries, each [entity, hull, layers, y_min, y_max, hurtbox rid], appended
## in serial order (the stepper's), so every query answers in serial order.
var _cells: Dictionary = {}


## Index every piece in `a_entities` (serial order) that has a Hurtbox in the tree.
func rebuild(a_entities: Array) -> void:
	_cells.clear()
	for item: Variant in a_entities:
		if not is_instance_valid(item):
			continue
		var entity: Entity = item
		if not entity.is_inside_tree() or entity.hurtbox == null:
			continue
		var shape_node := entity.hurtbox.get_node_or_null("HurtboxShape") as CollisionShape3D
		if shape_node == null or shape_node.shape == null or not shape_node.is_inside_tree():
			continue
		var half: float = (
			Entity._half_height_of(shape_node.shape) * shape_node.global_transform.basis.y.length()
		)
		var y: float = shape_node.global_position.y
		var hull: Hull = entity.hull()
		var entry: Array = [
			entity,
			hull,
			entity.hurtbox.collision_layer,
			y - half,
			y + half,
			entity.hurtbox.get_rid()
		]
		for cell: Vector2i in _cells_around(hull.center, hull.extent()):
			if not _cells.has(cell):
				_cells[cell] = []
			(_cells[cell] as Array).append(entry)


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
