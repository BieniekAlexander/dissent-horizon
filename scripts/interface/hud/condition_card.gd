class_name ConditionCard
extends VerboseTooltipButton

## ONE CARD FOR ANYTHING TRUE OF A SELECTED PIECE — a status effect acting on it, a passive
## ability it carries. Both rows in the info panel build through this, so the two read as one
## vocabulary rather than as two families of badge that happen to sit near each other.
##
## THE MODELS ARE STILL SEPARATE and this does not pretend otherwise (see
## gdd/systems/ux/ui/condition-cards.md §Two constructs, one card): a StatusEffect is a node on
## the host with a duration, a passive is an id in a table. What is shared is the QUESTION a
## player asks of either — *what is this, is it helping me, and will it last?* — so the card
## is shared and the models are not.
##
## THREE CHANNELS, each answering one of those and each readable without the other two:
##
##   VALENCE    a coloured edge — green at the TOP for a boon, red at the BOTTOM for an
##              affliction, nothing for neutral. Position as well as colour, so the pair
##              survives a colour-blind reader and a grey screenshot.
##   DURATION   a depletion sweep across the card's base, draining as it runs out. A
##              PERSISTENT condition draws none at all — absence is the signal, and it is a
##              stronger one than a full bar, which reads as "just started".
##   RATE       a small figure in the corner, for a condition that PRODUCES something — what
##              this piece is banking per cycle. Drawn only when there is a number to show,
##              so an ordinary condition is unchanged.
##   AVAILABILITY  the whole card greys when the condition is real but not yet YOURS — an
##              unbought passive its faction offers. Borrowed from
##              CommandButtonState.TINT_LOCKED so "you have not paid for this" looks the same
##              here as on an ability's own button.
##
## Nothing is pressable. A condition is a statement about the piece, not an option, and the
## plain pointer says so.

#region Constants
const CARD_SIZE: Vector2 = Vector2(28, 28)
const LETTER_FONT_SIZE: int = 15
const LETTER_COLOR: Color = Color(0.86, 0.87, 0.86)

## Thickness of the valence edge, and of the duration sweep. Both are thin: they qualify the
## card rather than competing with the glyph on it.
const EDGE_HEIGHT: float = 3.0
const SWEEP_HEIGHT: float = 3.0
const SWEEP_COLOR: Color = Color(0.88, 0.89, 0.90, 0.85)
const SWEEP_BACKING: Color = Color(0.0, 0.0, 0.0, 0.45)

## The rate figure. Small, bottom-right, and outlined so it stays legible over art — the same
## treatment and the same corner as a command button's charge count, so "a number in that
## corner is a quantity this thing holds" means one thing across the HUD.
const BADGE_FONT_SIZE: int = 9
const BADGE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.92)
#endregion

#region Properties
## Is this good or bad for the piece? Drives the edge.
var valence: Valence.Kind = Valence.Kind.NEUTRAL

## Does it run out? A persistent condition draws no sweep.
var is_temporary: bool = false

## Fraction of its life remaining, 0..1. Ignored unless `is_temporary`. Refreshed every frame
## by the owning row, because a duration moves while the selection stands still.
var remaining: float = 1.0

var _badge: Label = null
var _edge: ColorRect = null
var _sweep_backing: ColorRect = null
var _sweep: ColorRect = null
#endregion


#region Construction
## Build a card. `a_glyph_texture` wins over `a_letter` when both are given — the letter is
## the stand-in for a condition with no art yet.
##
## TODO: every condition without an `indicator_icon` draws a letter. Real art replaces the
## label and nothing else; the three channels below are independent of it.
static func build(
	a_name: String,
	a_letter: String,
	a_glyph_texture: Texture2D,
	a_valence: Valence.Kind,
	a_is_temporary: bool
) -> ConditionCard:
	var card := ConditionCard.new()
	card.name = a_name
	card.custom_minimum_size = CARD_SIZE
	card.focus_mode = Control.FOCUS_NONE
	card.mouse_default_cursor_shape = Control.CURSOR_ARROW
	card.valence = a_valence
	card.is_temporary = a_is_temporary
	card._build_face(a_letter, a_glyph_texture)
	return card


func _build_face(a_letter: String, a_glyph_texture: Texture2D) -> void:
	if a_glyph_texture != null:
		var icon := TextureRect.new()
		icon.texture = a_glyph_texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(icon)
	else:
		var label := Label.new()
		label.text = a_letter
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.add_theme_font_size_override("font_size", LETTER_FONT_SIZE)
		label.add_theme_color_override("font_color", LETTER_COLOR)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)

	# THE EDGE. Anchored explicitly rather than by preset: a PRESET_TOP_WIDE box grows DOWN
	# and a PRESET_BOTTOM_WIDE box grows DOWN as well, which is the mistake that put every
	# CommandableCard's status bar below its card (CLAUDE.md §Seeing the HUD without a screen).
	if valence != Valence.Kind.NEUTRAL:
		_edge = ColorRect.new()
		_edge.name = "Edge"
		_edge.color = Valence.color_of(valence)
		_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_edge.anchor_left = 0.0
		_edge.anchor_right = 1.0
		var at_top: bool = valence == Valence.Kind.BOON
		_edge.anchor_top = 0.0 if at_top else 1.0
		_edge.anchor_bottom = 0.0 if at_top else 1.0
		_edge.offset_top = 0.0 if at_top else -EDGE_HEIGHT
		_edge.offset_bottom = EDGE_HEIGHT if at_top else 0.0
		add_child(_edge)

	# THE SWEEP, only for something that runs out. A persistent condition has no bar at all.
	if not is_temporary:
		return
	# LIFTED CLEAR OF A BANE'S EDGE, which sits in the same strip: drawn last, the sweep
	# covered the red entirely and only let it show where it had drained — so an affliction
	# read as an affliction only once it was nearly over.
	var lift: float = EDGE_HEIGHT if valence == Valence.Kind.BANE else 0.0
	_sweep_backing = _make_sweep_rect(SWEEP_BACKING, 1.0, lift)
	_sweep = _make_sweep_rect(SWEEP_COLOR, 1.0, lift)


## A full-width strip along the card's base, `a_lift` pixels clear of it. `a_fill` is its
## right anchor, so draining is one property write and needs no layout code.
func _make_sweep_rect(a_color: Color, a_fill: float, a_lift: float) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = a_color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.anchor_left = 0.0
	rect.anchor_right = a_fill
	rect.anchor_top = 1.0
	rect.anchor_bottom = 1.0
	rect.offset_top = -SWEEP_HEIGHT - a_lift
	rect.offset_bottom = -a_lift
	add_child(rect)
	return rect


#endregion


#region Live state
## Repaint everything that moves while the selection stands still: how much of a duration is
## left, whether the condition is yours yet, and what it is producing.
##
## `a_badge` is created on first use and hidden when empty, so a card that never carries a
## rate never allocates a label for one.
func refresh(a_remaining: float, a_enabled: bool, a_badge: String = "") -> void:
	remaining = clampf(a_remaining, 0.0, 1.0)
	if _sweep != null:
		_sweep.anchor_right = remaining
	modulate = CommandButtonState.TINT_AVAILABLE if a_enabled else CommandButtonState.TINT_LOCKED
	if a_badge.is_empty():
		if _badge != null:
			_badge.visible = false
		return
	if _badge == null:
		_badge = Label.new()
		_badge.name = "Badge"
		# FULL RECT plus alignment, never a sized-and-offset box: the offset arithmetic is
		# exactly what put every CommandableCard status bar below its card.
		_badge.set_anchors_preset(Control.PRESET_FULL_RECT)
		_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_badge.add_theme_font_size_override("font_size", BADGE_FONT_SIZE)
		_badge.add_theme_color_override("font_color", BADGE_COLOR)
		_badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		_badge.add_theme_constant_override("outline_size", 3)
		_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_badge)
	_badge.visible = true
	_badge.text = a_badge
#endregion
