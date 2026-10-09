class_name Lattice
extends RefCounted

## A COARSE GRID OVER THE MAP, CENTRED ON IT: the one geometry every spatial read shares.
##
## A lattice is a pitch, a width and depth in cells, and the world XZ of cell (0, 0)'s min
## corner. `covering` lays one over a world rectangle so that the cell boundaries are SYMMETRIC
## ABOUT THE RECTANGLE'S CENTRE: a point and its reflection through the centre land in cells
## that are each other's `reflected` partner. That is the whole reason this class exists. The
## bot's scout grid used to quantise the map from its min corner with a rounding that was not
## carried onto itself by the map's reflection, so two commanders on a mirrored map
## partitioned it differently and scouted it unequally (gdd/systems/ai/bot-architecture.md
## §Where a building goes, the start-position bias). Every lattice channel the bot keeps —
## sight age, passability, the distance fields — is indexed by this object, so none of them
## can reintroduce a world axis. Rule: gdd/systems/ai/world-model/lattice-and-topology.md
## §One lattice and §Determinism.
##
## Indexing is unbounded on purpose: `index_at` floors any point to a cell and `is_in_bounds`
## is the separate question, so a sample taken off the edge of the map answers "that cell", and
## the caller decides. `anchored` builds a lattice with no extent at all, for a synthetic grid
## in a test that has no map to cover.

## Cells across (X) and down (Z); 0 for an `anchored` lattice, which has no extent.
var width: int = 0
var depth: int = 0
## World units from one cell's min corner to the next.
var pitch: float = 1.0
## World XZ of cell (0, 0)'s min corner.
var origin: Vector2 = Vector2.ZERO


#region Construction
## The lattice of `pitch` that covers `bounds`, with its cells centred on the bounds' centre:
## as many cells as the bounds need, laid out from the centre so an odd remainder is split
## evenly over both edges rather than pushed to one.
static func covering(bounds: Rect2, pitch: float) -> Lattice:
	var lattice := Lattice.new()
	lattice.pitch = pitch
	lattice.width = maxi(1, ceili(bounds.size.x / pitch))
	lattice.depth = maxi(1, ceili(bounds.size.y / pitch))
	var size := Vector2(float(lattice.width), float(lattice.depth)) * pitch
	lattice.origin = bounds.get_center() - size * 0.5
	return lattice


## A lattice with no extent, indexing from `origin` at `pitch` — for a synthetic grid whose
## cells a test writes by hand. `is_in_bounds` is false everywhere on it.
static func anchored(origin: Vector2, pitch: float) -> Lattice:
	var lattice := Lattice.new()
	lattice.pitch = pitch
	lattice.origin = origin
	return lattice


#endregion


#region Geometry
## The cell under a world XZ point. Unbounded: see the file comment.
func index_at(a_xz: Vector2) -> Vector2i:
	var scaled: Vector2 = (a_xz - origin) / pitch
	return Vector2i(floori(scaled.x), floori(scaled.y))


func is_in_bounds(a_cell: Vector2i) -> bool:
	return a_cell.x >= 0 and a_cell.x < width and a_cell.y >= 0 and a_cell.y < depth


## World XZ of a cell's centre.
func centre_of(a_cell: Vector2i) -> Vector2:
	return origin + (Vector2(a_cell) + Vector2(0.5, 0.5)) * pitch


## The world rectangle a cell covers.
func rect_of(a_cell: Vector2i) -> Rect2:
	return Rect2(origin + Vector2(a_cell) * pitch, Vector2(pitch, pitch))


## The cell a point reflected through the lattice's centre lands in: the mirror partner.
func reflected(a_cell: Vector2i) -> Vector2i:
	return Vector2i(width - 1 - a_cell.x, depth - 1 - a_cell.y)


func world_size() -> Vector2:
	return Vector2(float(width), float(depth)) * pitch


func centre() -> Vector2:
	return origin + world_size() * 0.5


#endregion


#region Flat indexing — row-major, as NavField and every channel store cells
func cell_count() -> int:
	return width * depth


func index_of(a_cell: Vector2i) -> int:
	return a_cell.y * width + a_cell.x


func cell_of(a_index: int) -> Vector2i:
	return Vector2i(a_index % width, a_index / width)
#endregion
