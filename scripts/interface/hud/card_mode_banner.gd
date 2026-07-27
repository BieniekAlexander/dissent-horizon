class_name CardModeBanner
extends Label

## WHICH CARD IS ON SCREEN, said in words and in colour.
##
## A STUB, deliberately: the three cards were distinguishable only by what happened to be
## drawn on them, so a player who pressed a key and got a grid of unfamiliar buttons had no
## way to tell whether they had changed cards or changed selection. This is the smallest thing
## that answers that — a title strip above the grid, plus a wash of the card's colour over the
## panel behind it. Refine or replace freely; nothing depends on how it looks.
##
## The COLOUR is the part worth keeping whatever the styling becomes. A title alone is read
## once and then stops being read, while a background tint is answered peripherally — which is
## what you want from a question ("where am I?") the player asks constantly and never
## deliberately.
##
## Built in code and parented by RTSController rather than authored into player.tscn, for the
## reason the rest of the generated HUD is: it is one file to delete when it is replaced.

## Per card: what it is called, and the colour that says so. Deliberately low-saturation —
## this washes a panel that already carries five button tints (see CommandButtonState), and a
## backdrop that competes with them would make the buttons harder to read, not easier.
const MODES: Dictionary = {
	ControlBinding.CommandFamily.ACTIVE: {
		"title": "ACTIVE", "color": Color(0.42, 0.52, 0.62),
	},
	ControlBinding.CommandFamily.PRODUCTION: {
		"title": "PRODUCTION", "color": Color(0.40, 0.56, 0.44),
	},
	ControlBinding.CommandFamily.ORDNANCE: {
		"title": "ORDNANCE", "color": Color(0.56, 0.44, 0.60),
	},
}

## HOW FAR ALONG AN ARMED ORDER IS. A fourth banner state rather than a fourth card: the card
## has been taken over by whatever is armed, and the question the banner answers ("where am
## I?") has a different answer from any of the three above.
##
## It reads in two, because "armed" covers two situations the player acts on differently:
##
##   PENDING — armed, and the card is still asking a question. A Build with no structure
##             chosen, a sanction with no cargo chosen. The next click is on the CARD.
##   READY   — armed and answered, or armed with nothing to answer. The next click is on
##             the MAP.
##
## Both keep the card's menu on screen alongside Cancel, so a player who picked the wrong
## structure can pick another without disarming first — which is why PENDING is a state of
## the banner and not a separate card.
enum ArmedState { NONE, PENDING, READY }

const ARMED_TITLES: Dictionary = {
	ArmedState.PENDING: "PENDING",
	ArmedState.READY: "READY",
}

## PENDING is the cooler, less urgent of the two: it means "keep choosing", where READY means
## "go and aim it". Both sit apart from the three card colours so neither can be mistaken for
## a card the player merely flipped to.
const ARMED_COLORS: Dictionary = {
	ArmedState.PENDING: Color(0.52, 0.50, 0.44),
	ArmedState.READY: Color(0.62, 0.56, 0.38),
}

## TODO: the words are stand-ins. This state wants visual elements naming the armed command
## and its tool — Alex flagged it for a later pass; see ui/control-matrices.md §Context 1a.

## How much of the card's colour reaches the panel behind the grid. Low, because it is
## answering a peripheral question and the buttons on top of it are the content.
const BACKDROP_BLEND: float = 0.55
const TITLE_HEIGHT: float = 15.0
const TITLE_FONT_SIZE: int = 10

## The panel this washes, and its authored colour — captured once so the blend is
## non-destructive and a card change recomputes from the original rather than from a
## previously tinted value.
var _backdrop: ColorRect = null
var _backdrop_base: Color = Color.WHITE


func _ready() -> void:
	# Sits ABOVE the grid's top edge: a full-width strip anchored to the top, grown UPWARD by a
	# negative offset. Stated explicitly rather than via a preset, because a PRESET_TOP_WIDE box
	# grows DOWN by default and would lie across the first row of buttons — the same mistake
	# that drew every CommandableCard status bar below its card (CLAUDE.md §Seeing the HUD).
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_top = -TITLE_HEIGHT
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	add_theme_constant_override("outline_size", 3)


## The panel to wash with the card's colour. Optional: with none, the banner is just a title.
func set_backdrop(a_backdrop: ColorRect) -> void:
	_backdrop = a_backdrop
	if a_backdrop != null:
		_backdrop_base = a_backdrop.color


## Show `a_family`, or one of the ARMED states when `a_armed` is not NONE — which overrides
## the card, because an armed order has taken the card over and naming the card it came from
## would be a lie.
##
## Unknown families leave the banner blank rather than erroring — a fourth card would be a
## design decision, not a crash.
func show_family(a_family: int, a_armed: ArmedState = ArmedState.NONE) -> void:
	var mode: Dictionary = MODES.get(a_family, {}) if a_armed == ArmedState.NONE \
		else {"title": ARMED_TITLES[a_armed], "color": ARMED_COLORS[a_armed]}
	text = str(mode.get("title", ""))
	var color: Color = mode.get("color", Color.WHITE)
	add_theme_color_override("font_color", color.lightened(0.45))
	if _backdrop != null:
		_backdrop.color = _backdrop_base.lerp(color, BACKDROP_BLEND) if not mode.is_empty() \
			else _backdrop_base
