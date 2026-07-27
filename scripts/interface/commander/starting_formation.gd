class_name StartingFormation
extends RefCounted

## Where a faction's opening units stand when a Skirmish deploys them.
##
## An AUTHORED formation is a scene whose Node3D children are the slots, one per starting
## unit, laid out in the XZ plane. This class is the pure geometry that turns those slots
## into world points: it reads the offsets, places the formation's origin toward the middle
## of the map, and rotates the whole arrangement so it faces that way.
##
## Nothing here touches the scene tree, the navmesh or a Map, so it is exercised without an
## engine running. Snapping the resulting points onto navigable ground is Map.add_entities'
## job, and it is the only thing standing between an authored slot and a bad spawn — see
## §At the edges in gdd/systems/scenario-scripting/starting-formations.md.

#region Constants
## How far CLEAR OF THE STARTING STRUCTURE the formation's origin sits, in GRID CELLS.
## Converted to world units by the caller against Map.CELL_SIZE, so the distance stays
## "three tiles" whatever a tile is worth.
##
## Measured from the structure's FOOTPRINT EDGE, not its centre — see extent_toward. A
## centre-relative gap means a different clearance for every faction, because their opening
## structures differ in size: three tiles from the centre of a 5×5 command centre leaves
## half a tile of daylight, while three from a 1×1 leaves two and a half. The units then
## deploy visibly tighter for one faction than another, for a reason nobody chose.
const DISTANCE_CELLS: float = 3.0

## The direction a formation scene is AUTHORED facing, in world XZ: −Z, which is up-screen
## (north) and Godot's own forward. A slot with a negative Z is in front of the formation —
## between the base and the middle of the map — and a positive Z is behind it.
##
## It doubles as the fallback heading for a start point that sits exactly on the play area's
## centre, where "toward the middle" names no direction at all. That reproduces the old
## behaviour of deploying due north, which is the right thing for a case with no better
## answer.
const AUTHORED_FACING: Vector2 = Vector2(0.0, -1.0)
#endregion

#region Reading a formation scene
## The slot offsets in `formation`, in world XZ and in CHILD ORDER — starting unit i takes
## child i. Non-Node3D children are ignored, so a formation scene may carry annotations.
##
## An empty result means "no formation": either the scene has no slots, or there was none.
## The caller compares the count against its own unit list; see Skirmish, which treats a
## mismatch as an authoring error rather than deploying half a formation.
static func offsets_from(formation: Node) -> Array[Vector2]:
	var offsets: Array[Vector2] = []
	if formation == null:
		return offsets
	for child: Node in formation.get_children():
		var slot := child as Node3D
		if slot != null:
			offsets.append(VU.inXZ(slot.position))
	return offsets
#endregion

#region Placing it
## The unit heading from `structure_xz` toward `center` — which way "into the map" is from
## this start point. AUTHORED_FACING when the two coincide, so the direction is always a
## real one.
static func heading_toward(structure_xz: Vector2, center: Vector2) -> Vector2:
	var toward: Vector2 = center - structure_xz
	return AUTHORED_FACING if toward.is_zero_approx() else toward.normalized()


## How far the footprint edge lies from the footprint CENTRE along `heading`, in world
## units, for an axis-aligned rectangle of `half_extents`.
##
## A slab test: the ray from the centre leaves the rectangle at the NEARER of the two
## bounding planes it heads for, so a diagonal heading exits through a side rather than a
## corner. Structures are axis-aligned in world XZ by construction — the grid is
## `Vector2i(x, z)` and nothing rotates a footprint — so the rectangle needs no basis.
##
## Zero half-extents give zero, which is what makes a structure-less caller behave exactly
## as it did when the gap was measured from the centre.
static func extent_toward(half_extents: Vector2, heading: Vector2) -> float:
	if half_extents.is_zero_approx() or heading.is_zero_approx():
		return 0.0
	var direction: Vector2 = heading.normalized()
	var reach: float = INF
	if absf(direction.x) > AXIS_EPSILON:
		reach = minf(reach, half_extents.x / absf(direction.x))
	if absf(direction.y) > AXIS_EPSILON:
		reach = minf(reach, half_extents.y / absf(direction.y))
	return reach if is_finite(reach) else 0.0


## Half the world-space size of a `dimensions`-cell footprint.
static func half_extents_of(dimensions: Vector2i, cell_size: float) -> Vector2:
	return Vector2(dimensions) * cell_size * 0.5


## Below which a heading component counts as parallel to an axis, so extent_toward skips
## that slab rather than dividing by it.
const AXIS_EPSILON: float = 1e-6


## Where the formation's own origin sits: `clearance` world-units beyond the structure's
## footprint edge, along the heading into the map. Always INWARD, which is what keeps a
## start point in a corner from deploying its units off the edge.
static func anchor(
	structure_xz: Vector2,
	center: Vector2,
	clearance: float,
	half_extents: Vector2 = Vector2.ZERO
) -> Vector2:
	var heading: Vector2 = heading_toward(structure_xz, center)
	return structure_xz + heading * (extent_toward(half_extents, heading) + clearance)


## One world-XZ point per slot: the formation anchored `clearance` beyond the structure's
## footprint edge toward `center`, and rotated so its authored facing points that same way.
##
## The rotation is exact by construction — every offset turns through the angle that carries
## AUTHORED_FACING onto the heading — so a formation authored with its leader in front keeps
## its leader in front whichever corner of the map it deploys from.
##
## `half_extents` defaults to zero, which measures the clearance from the structure's centre
## as this did before footprints were taken into account. A caller that knows the footprint
## should pass it; one that does not gets the old behaviour rather than a wrong one.
static func world_points(
	offsets: Array[Vector2],
	structure_xz: Vector2,
	center: Vector2,
	clearance: float,
	half_extents: Vector2 = Vector2.ZERO
) -> Array[Vector2]:
	var heading: Vector2 = heading_toward(structure_xz, center)
	var turn: float = AUTHORED_FACING.angle_to(heading)
	var origin: Vector2 = anchor(structure_xz, center, clearance, half_extents)
	var points: Array[Vector2] = []
	for offset: Vector2 in offsets:
		points.append(origin + offset.rotated(turn))
	return points
#endregion
