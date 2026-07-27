@tool
class_name MapStart
extends RefCounted

## Where one player begins, and which alliance they belong to. Everything downstream of start
## placement reads only this — never how the starts were chosen (map-generation.md §2).

#region Properties
## Continuous cell-space position (see MapFeature).
var position: Vector2 = Vector2.ZERO
var alliance: int = 0
#endregion


static func at(position: Vector2, alliance: int) -> MapStart:
	var start := MapStart.new()
	start.position = position
	start.alliance = alliance
	return start
