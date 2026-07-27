@tool
class_name MapPiece
extends RefCounted

## A piece the map generator may place, reduced to what placement needs: its id and its
## footprint. The generator never loads a scene — the shell that writes the map resolves the
## id back to one — so a piece is data here, and a pool of them is a generation parameter.

#region Properties
## The piece's spec-doc id (EntityIds.*).
var id: StringName = &""
## Footprint in cells, x by z.
var footprint: Vector2i = Vector2i.ONE
## Relative draw weight within a pool. Meaningless for a piece that is not in one.
var weight: float = 1.0
#endregion


static func of(id: StringName, footprint: Vector2i, weight: float = 1.0) -> MapPiece:
	var piece := MapPiece.new()
	piece.id = id
	piece.footprint = footprint
	piece.weight = weight
	return piece


func cell_count() -> int:
	return footprint.x * footprint.y
