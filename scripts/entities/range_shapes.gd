class_name RangeShapes
extends RefCounted

## The volumes that measure how far a piece reaches, and the rule that derives its AGGRO from
## that reach. Aggro is never authored: a piece picks fights at a radius its weapons imply, per
## target layer, so retuning a reach bucket moves the engagement radius with it. Why, and the
## history: gdd/systems/combat/range-buckets.md.

## The height of every range volume — weapon reach, aggro, vision and the bodies. Far taller
## than the world so that a slope or a flier's cruise altitude never decides an overlap; only
## the radius is meaningful. The spec importer writes this into every doc-governed cylinder.
const SHAPE_HEIGHT: float = 100.0

## The aggro rule: one unit past reach, never below MIN nor above MAX.
const AGGRO_MARGIN: float = 1.0
const AGGRO_MIN_RADIUS: float = 5.0
const AGGRO_MAX_RADIUS: float = 10.0

## One shared cylinder per aggro radius, so every piece with the same reach holds the same
## resource — the runtime counterpart of the reach-bucket library. Memoized because a shape
## per piece would be a resource per piece; entries are never mutated, only handed out.
static var _aggro_shapes: Dictionary = {}


## The aggro radius a reach implies, or -1.0 for no reach at all.
##
## A piece that CANNOT MOVE is additionally held to its reach: it cannot walk toward what it
## latches onto, so acquiring past reach would lock it onto a target it can never fire on
## (see Attack.get_updated_state's stationary leash).
static func aggro_radius_for_reach(reach: float, can_move: bool) -> float:
	if reach < 0.0:
		return -1.0
	var radius: float = clampf(reach + AGGRO_MARGIN, AGGRO_MIN_RADIUS, AGGRO_MAX_RADIUS)
	return radius if can_move else minf(radius, reach)


## The shared aggro shape for a reach, or null for no reach.
static func aggro_shape_for_reach(reach: float, can_move: bool) -> CylinderShape3D:
	var radius: float = aggro_radius_for_reach(reach, can_move)
	if radius < 0.0:
		return null
	if not _aggro_shapes.has(radius):
		var shape := CylinderShape3D.new()
		shape.height = SHAPE_HEIGHT
		shape.radius = radius
		_aggro_shapes[radius] = shape
	return _aggro_shapes[radius]


## XZ radius of a range node — shape radius scaled by the node's X axis — or -1.0 for a
## missing node, a cleared shape, or a shape that is not round.
static func xz_radius(shape_node: CollisionShape3D) -> float:
	if shape_node == null:
		return -1.0
	var scale: float = (
		shape_node.global_transform.basis.x.length()
		if shape_node.is_inside_tree()
		else shape_node.transform.basis.x.length()
	)
	var radius: float = radius_of(shape_node.shape)
	return radius * scale if radius >= 0.0 else -1.0


## The radius of a round library shape, unscaled, or -1.0 for null or anything else.
static func radius_of(shape: Shape3D) -> float:
	if shape is CylinderShape3D:
		return (shape as CylinderShape3D).radius
	if shape is SphereShape3D:
		return (shape as SphereShape3D).radius
	return -1.0
