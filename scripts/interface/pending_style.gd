class_name PendingStyle
extends RefCounted

## How the HUD draws a PENDING piece's effect — something ordered that is not active yet — so
## every readout says "this will happen" the same way. The rule and the other tenses (real,
## preview, projection) it has to stay distinct from: gdd/systems/ux/README.md §Pending pieces
## are shown, as pending.
##
## TODO: the idiom itself is a placeholder awaiting a decision — see that section's proposals.

## Alpha a bar region or ring drawn for pending pieces carries: the real colour, see-through.
const ALPHA: float = 0.4

## A world-space outline drawn for a pending piece is DASHED: this long a dash, and this long a
## gap, in metres along the outline.
const DASH_METRES: float = 0.9
const GAP_METRES: float = 0.6


## `a_color` as a pending piece's effect draws it.
static func of(a_color: Color) -> Color:
	return Color(a_color.r, a_color.g, a_color.b, a_color.a * ALPHA)
