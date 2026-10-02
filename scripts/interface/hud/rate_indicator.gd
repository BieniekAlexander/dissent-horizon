class_name RateIndicator
extends Control

## A small, always-on, NON-TEXT readout of one or two "rate" figures beside a resource bar —
## a short vertical bar per rate, height = that rate's fraction of an authored visual scale.
##
## Exists because EconomyStack already prints rates as digits under ui_verbose; this is the
## SHALLOW tier for the same numbers, which is the point of the persistent bars — see
## gdd/systems/ux/ui/economy-bars.md §Rates get a shallow tier too.

#region Constants
const WIDTH: float = 22.0
const BAR_GAP: float = 3.0
const TRACK_COLOR: Color = ResourcePressure.PANEL_COLOR
#endregion

#region Properties
## Set once by the owning bar before this enters the tree.
var height: float = 18.0

## One dictionary per bar: {color: Color, value: float, scale: float}, and optionally `pending`:
## how much ordered-but-unfinished pieces will add, stacked on top in PendingStyle. Rebuilt by
## the owning bar every refresh rather than diffed — it is a couple of numbers and a colour,
## not worth a change-detection path.
var bars: Array = []
#endregion


#region Lifecycle
func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, height)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	draw.connect(_on_draw)


#endregion


#region Drawing
func _on_draw() -> void:
	if bars.is_empty():
		return
	var bar_width: float = (WIDTH - BAR_GAP * (bars.size() - 1)) / float(bars.size())
	for i in bars.size():
		var entry: Dictionary = bars[i]
		var x: float = i * (bar_width + BAR_GAP)
		draw_rect(Rect2(x, 0.0, bar_width, height), TRACK_COLOR)
		var scale: float = maxf(float(entry.get("scale", 1.0)), 0.0001)
		var frac: float = clampf(float(entry.get("value", 0.0)) / scale, 0.0, 1.0)
		var fill_height: float = height * frac
		var color: Color = entry.get("color", Color.WHITE) as Color
		if fill_height > 0.0:
			draw_rect(Rect2(x, height - fill_height, bar_width, fill_height), color)
		var pending_frac: float = clampf(
			(float(entry.get("value", 0.0)) + maxf(float(entry.get("pending", 0.0)), 0.0)) / scale,
			0.0,
			1.0
		)
		var pending_height: float = height * pending_frac - fill_height
		if pending_height > 0.0:
			draw_rect(
				Rect2(x, height - fill_height - pending_height, bar_width, pending_height),
				PendingStyle.of(color)
			)
#endregion
