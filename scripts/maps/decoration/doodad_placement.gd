@tool
class_name DoodadPlacement
extends RefCounted

## One cosmetic prop. Position is in CELL space — x, z continuous over the grid (cell (x, z)
## spans [x, x+1)), y the ground height there — so it is independent of where the Map sits.

var kind: DoodadLibrary.Kind = DoodadLibrary.Kind.GRASS_TUFT
var position: Vector3 = Vector3.ZERO
var yaw_radians: float = 0.0
var scale: float = 1.0
## The cell it stands in, so a structure placed later can clear what it covers.
var cell: Vector2i = Vector2i.ZERO


static func of(
	kind: DoodadLibrary.Kind, position: Vector3, yaw_radians: float, scale: float
) -> DoodadPlacement:
	var placement := DoodadPlacement.new()
	placement.kind = kind
	placement.position = position
	placement.yaw_radians = yaw_radians
	placement.scale = scale
	placement.cell = Vector2i(floori(position.x), floori(position.z))
	return placement
