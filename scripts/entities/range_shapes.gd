class_name RangeShapes
extends RefCounted

## The volumes that measure how far a piece reaches, and the rule that derives its AGGRO from
## that reach. Aggro is never authored: a piece picks fights at its reach, per target layer, so
## retuning a reach bucket moves the engagement radius with it. Why, and the history:
## gdd/systems/combat/range-buckets.md.

## The height of every range volume — weapon reach, aggro, vision and the bodies. Far taller
## than the world so that a slope or a flier's cruise altitude never decides an overlap; only
## the radius is meaningful. The spec importer writes this into every doc-governed cylinder.
const SHAPE_HEIGHT: float = 100.0

## The generated shape-library entry that marks the artillery boundary. A weapon whose reach is
## BELOW its radius fires along the ground and is stopped by terrain on the line
## (Attack._terrain_on_line); at or above it, the shot is lobbed.
const ARTILLERY_SHAPE_PATH: String = "res://resources/generated/shapes/ground_range_artillery.tres"


## The artillery reach in world units, read from the imported shape so retuning the bucket in
## gdd/shapes/shapes.md moves the rule with it. -1.0 if the shape is missing or not round.
static func artillery_reach() -> float:
	return radius_of(load(ARTILLERY_SHAPE_PATH) as Shape3D)


## The aggro rule (Alex, 2026-10-19): a piece picks fights at its REACH, per target layer — no
## margin past it, no floor or ceiling around it — except that a reach shorter than the
## `ground_range_short` bucket aggros at that bucket, so a melee piece notices what is about to
## reach it. The floor is read from the imported shape, so retuning the bucket moves it.
const AGGRO_FLOOR_SHAPE_PATH: String = "res://resources/generated/shapes/ground_range_short.tres"


## The aggro floor in world units (see AGGRO_FLOOR_SHAPE_PATH); 0.0 when the shape is missing.
static func aggro_floor() -> float:
	if _aggro_floor < 0.0:
		_aggro_floor = maxf(radius_of(load(AGGRO_FLOOR_SHAPE_PATH) as Shape3D), 0.0)
	return _aggro_floor


static var _aggro_floor: float = -1.0

## One shared cylinder per aggro radius, so every piece with the same reach holds the same
## resource — the runtime counterpart of the reach-bucket library. Memoized because a shape
## per piece would be a resource per piece; entries are never mutated, only handed out.
static var _aggro_shapes: Dictionary = {}


## The aggro radius a reach implies, or -1.0 for no reach at all: the reach itself, or the
## aggro floor for a reach under it.
##
## A piece that CANNOT MOVE takes no floor: it cannot walk toward what it latches onto, so
## acquiring past reach would lock it onto a target it can never fire on (see
## Attack.get_updated_state's stationary leash).
static func aggro_radius_for_reach(reach: float, can_move: bool) -> float:
	if reach < 0.0:
		return -1.0
	return maxf(reach, aggro_floor()) if can_move else reach


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
