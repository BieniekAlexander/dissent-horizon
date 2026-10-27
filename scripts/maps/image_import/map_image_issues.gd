@tool
class_name MapImageIssues
extends RefCounted

## A refused drawing's issues, each an error with the pixels it is about (map-from-image.md §The
## report): numbered and coloured, so a report line and the readout's marks can be matched — and
## the dock's readout names the issue under the pointer.

#region Constants
## One colour per issue, cycled, each named in the report line it marks. Saturated and opaque so
## they stand out over every palette colour.
const COLORS: Array[Color] = [
	Color(1.0, 0.0, 0.0),
	Color(1.0, 0.85, 0.0),
	Color(0.0, 1.0, 1.0),
	Color(0.2, 1.0, 0.2),
	Color(1.0, 0.5, 0.0),
	Color(0.6, 0.2, 1.0),
]
const COLOR_NAMES: PackedStringArray = ["red", "yellow", "cyan", "green", "orange", "violet"]
#endregion


## The issues that mark pixels, in the order raised: {message, pixels}. Empty when the import was
## refused before the drawing was classified — an unreadable file, an unknown layer.
static func of(result: MapImageImporter) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if result.cells == null:
		return out
	for issue: Dictionary in result.cells.issues:
		if not (issue.pixels as Array).is_empty():
			out.append(issue)
	return out


## The report line for issue `index`, naming the colour it is marked in.
static func line(index: int, message: String) -> String:
	return "[%d, %s] %s" % [index + 1, COLOR_NAMES[index % COLOR_NAMES.size()], message]
