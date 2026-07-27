class_name EconomyBar
extends Control

## Base for a persistent, horizontal resource bar: a fill that grows to the right, scaled
## against a "capacity" that gives its fraction meaning, a value label on its right, and —
## while ui_verbose is held — a second line of rate detail beneath it.
##
## Subclasses (EnergyBar/InfrastructureBar/DominionBar) supply WHAT is measured and HOW it is
## coloured by overriding the §Overridable methods; this owns the drawing and the segment
## lines. Built in code, like ProductionRail: three near-identical trees with no fixed shape
## for the editor to hold.
##
## Full write-up: gdd/systems/ux/ui/economy-bars.md.

#region Constants
const BAR_HEIGHT: float = 18.0
## The same near-opaque backing every persistent HUD panel sits on — legible against any
## world background. See ResourcePressure.PANEL_COLOR.
const BAR_BG_COLOR: Color = ResourcePressure.PANEL_COLOR
const SEGMENT_LINE_COLOR: Color = Color(0.0, 0.0, 0.0, 0.45)
const TEXT_COLOR: Color = Color(0.86, 0.87, 0.86)
const MUTED_COLOR: Color = Color(0.60, 0.63, 0.59)
const VALUE_FONT_SIZE: int = 15
const VERBOSE_FONT_SIZE: int = 11
const LABEL_GUTTER: float = 8.0
## How far a hover-preview colour sits toward BAR_BG_COLOR — see _dimmed().
const PREVIEW_MIX: float = 0.55
## Alpha for a PERSISTENT rate projection past the real fill — see _rate_regions() and
## _at_alpha(). Deliberately a plain alpha cut, not a mix toward the background like
## _dimmed(): a rate region sits past the real fill, never on top of an identically-coloured
## one, so it has no self-cancelling composite to avoid (see _dimmed()'s own comment).
const RATE_BAR_ALPHA: float = 0.5
#endregion

#region Properties
## The commander whose economy this shows. Injected by RTSController at _ready. Set before
## this node enters the tree in code-built HUD assembly.
var commander: Commander = null

## Injected alongside `commander` — read for the one thing a bar cannot get from Commander
## alone: what the pointer is currently hovering, for the purchase-preview overlay (see
## §Overridable and gdd/systems/ux/ui/economy-bars.md §Hover previews). Null-safe: every hover
## lookup treats a missing controller the same as nothing being hovered.
var controller: RTSController = null

## Set before add_child — the bar's pixel width.
var bar_width: float = 208.0

var _fill: Control
var _value_label: Label
var _verbose_label: Label
#endregion

#region Lifecycle
func _ready() -> void:
	custom_minimum_size = Vector2(bar_width, BAR_HEIGHT + VERBOSE_FONT_SIZE + 4.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var background := ColorRect.new()
	background.color = BAR_BG_COLOR
	background.position = Vector2.ZERO
	background.size = Vector2(bar_width, BAR_HEIGHT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	_fill = Control.new()
	_fill.name = "Fill"
	_fill.position = Vector2.ZERO
	_fill.size = Vector2(bar_width, BAR_HEIGHT)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill.draw.connect(_draw_fill)
	add_child(_fill)

	_value_label = _make_label(VALUE_FONT_SIZE, TEXT_COLOR)
	_value_label.position = Vector2(bar_width + LABEL_GUTTER, -3.0)
	add_child(_value_label)

	_verbose_label = _make_label(VERBOSE_FONT_SIZE, MUTED_COLOR)
	_verbose_label.position = Vector2(0.0, BAR_HEIGHT + 2.0)
	_verbose_label.visible = false
	add_child(_verbose_label)

	refresh()

func _process(_a_delta: float) -> void:
	refresh()
#endregion

#region Public API
func refresh() -> void:
	if commander == null:
		return
	_fill.queue_redraw()
	_value_label.text = _value_text()
	_verbose_label.visible = Input.is_action_pressed("ui_verbose") and _has_verbose_text()
	if _verbose_label.visible:
		_verbose_label.text = _verbose_text()
#endregion

#region Drawing
## Paints the regions _fill_regions() describes, then _rate_regions() (a PERSISTENT
## projection, e.g. DominionBar's 60-second income forecast), then the segment dividers, then
## the hover-preview regions LAST so the dim overlay reads clearly on top of everything real.
## Dividers are drawn across the WHOLE bar rather than only the filled part, since
## InfrastructureBar's two regions together always cover the entire bar and a divider is a
## fact about the SCALE, not about how much of it is currently used.
func _draw_fill() -> void:
	if commander == null:
		return
	var capacity: float = maxf(_capacity(), 0.0001)
	_draw_regions(_fill_regions())
	_draw_regions(_rate_regions())
	for segment_frac: float in BarGradient.segment_fractions(capacity, _segment_size()):
		var x: float = bar_width * segment_frac
		_fill.draw_line(Vector2(x, 0.0), Vector2(x, BAR_HEIGHT), SEGMENT_LINE_COLOR, 1.0)
	_draw_regions(_preview_regions())

func _draw_regions(a_regions: Array[Dictionary]) -> void:
	for region: Dictionary in a_regions:
		var x0: float = bar_width * clampf(region.start_frac, 0.0, 1.0)
		var x1: float = bar_width * clampf(region.end_frac, 0.0, 1.0)
		if x1 > x0:
			_fill.draw_rect(Rect2(x0, 0.0, x1 - x0 + 0.5, BAR_HEIGHT), region.color as Color)

func _make_label(a_font_size: int, a_color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", a_font_size)
	label.add_theme_color_override("font_color", a_color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
#endregion

#region Overridable
## The pool's current amount.
func _current_value() -> float:
	return 0.0

## The bar's visual full scale — what "100% filled" means. Never the true unbounded maximum
## for a pool that has none (energy); see each subclass for what it picks.
func _capacity() -> float:
	return 1.0

## The flat-coloured regions to paint, each `{start_frac, end_frac, color}` in fractions of
## _capacity(). The default is ONE region, [0, value/capacity], in _fill_color()'s colour at
## the overall fraction — a single flat fill, per gdd/tasks.md "UI Updates": the colour is
## chosen from where the fill SITS on the ramp, not painted as a ramp across the fill.
## InfrastructureBar overrides this for its two-region used/excess picture.
func _fill_regions() -> Array[Dictionary]:
	var frac: float = clampf(_current_value() / maxf(_capacity(), 0.0001), 0.0, 1.0)
	if frac <= 0.0:
		return []
	return [{"start_frac": 0.0, "end_frac": frac, "color": _fill_color(frac)}]

## The fill's colour at `a_frac` of the capacity scale (already clamped to [0, 1]). Only
## consulted by the default _fill_regions() above.
func _fill_color(_a_frac: float) -> Color:
	return Color.WHITE

## The width, in the same units as _capacity(), of one segment divider — e.g. one
## infrastructure provider's grant. 0 (the default) draws no dividers.
func _segment_size() -> float:
	return 0.0

## The right-hand numeric readout.
func _value_text() -> String:
	return ""

## Whether _verbose_text() has anything to say — a faction with no dominion generators, say,
## has no rate line to show even while ui_verbose is held.
func _has_verbose_text() -> bool:
	return false

## The ui_verbose-only line beneath the bar.
func _verbose_text() -> String:
	return ""

## The dim, temporary regions showing what a hovered purchase would do to this pool — see
## gdd/systems/ux/ui/economy-bars.md §Hover previews. Same shape as _fill_regions().
##
## The default reading is "value against a cost": draws the interval between the pool's
## current value and value±_preview_cost(), whichever side of `value` the cost falls on —
## the portion that would be SPENT when affordable, or the portion still MISSING when not.
## EnergyBar/DominionBar only need to supply _preview_cost(); InfrastructureBar overrides
## this method entirely, since its preview is not a value-against-a-cost comparison at all.
func _preview_regions() -> Array[Dictionary]:
	var cost: float = _preview_cost()
	if cost <= 0.0:
		return []
	var capacity: float = maxf(_capacity(), 0.0001)
	var value: float = _current_value()
	var start: float = value - cost if cost <= value else value
	var end: float = value if cost <= value else cost
	var end_frac: float = clampf(end / capacity, 0.0, 1.0)
	return [{
		"start_frac": clampf(start / capacity, 0.0, 1.0),
		"end_frac": end_frac,
		"color": _dimmed(_fill_color(end_frac)),
	}]

## The cost, in this bar's own unit, of whatever purchase is currently hovered — 0 (the
## default: no preview) when nothing relevant is hovered. Consulted only by the default
## _preview_regions() above.
func _preview_cost() -> float:
	return 0.0

## A PERSISTENT region past the real fill, at RATE_BAR_ALPHA — a projection, always on
## screen, as against _preview_regions()'s TEMPORARY hover-only one. Empty by default; only
## DominionBar supplies one today (a 60-second income forecast), but the hook is generic —
## see gdd/systems/ux/ui/economy-bars.md §Rate projection. Same shape as _fill_regions():
## `{start_frac, end_frac, color}` in fractions of _capacity(), clamped to [0, 1] so a
## projection bigger than the bar's own scale fills the remainder rather than overflowing.
func _rate_regions() -> Array[Dictionary]:
	return []

## `a_color` with its alpha replaced by `a_alpha` — what a persistent rate projection looks
## like (RATE_BAR_ALPHA), as plain alpha rather than _dimmed()'s background mix.
func _at_alpha(a_color: Color, a_alpha: float) -> Color:
	return Color(a_color.r, a_color.g, a_color.b, a_alpha)

## `a_color`, mixed PREVIEW_MIX of the way toward the panel background and drawn fully
## OPAQUE — what "not yet real" looks like everywhere a bar draws a hover preview.
##
## Opaque and pre-mixed rather than the same colour at reduced ALPHA: EnergyBar's affordable
## preview region ends exactly where the real fill already ends, in the exact colour
## _fill_color() gives that same position — compositing a translucent colour over an OPAQUE
## identical colour is a no-op (alpha blending: `c·a + c·(1-a) = c`), so the preview drew and
## was invisible. Mixing toward the background first changes the actual RGB, so it reads as a
## dimmer shade of the real colour whether it lands on top of the real fill (affordable) or on
## bare background past it (unaffordable) — see gdd/systems/ux/ui/economy-bars.md §Hover previews.
func _dimmed(a_color: Color) -> Color:
	var muted: Color = a_color.lerp(Color(BAR_BG_COLOR.r, BAR_BG_COLOR.g, BAR_BG_COLOR.b),
		PREVIEW_MIX)
	muted.a = 1.0
	return muted

## The Tool a purchase preview should be read against: whatever is hovered in the UI, or —
## if nothing purchase-shaped is hovered — whatever tool is currently ARMED
## (RTSController.previewed_tool(), which is also where the "hover wins outright, never
## combines with armed" rule lives). Null when there is no controller, or neither hover nor
## arming names a Tool purchase (a verb or an ability cast has no Tool at all).
func _previewed_tool() -> Tool:
	if controller == null:
		return null
	return controller.previewed_tool()

## The TechnologySpec for _previewed_tool(), or null. What EnergyBar/DominionBar's
## _preview_cost() reads; InfrastructureBar reads _previewed_tool() directly instead, since
## what it needs is the piece's own ongoing `infrastructure` export, not a TechnologySpec
## field.
func _hovered_spec() -> TechnologySpec:
	var tool: Tool = _previewed_tool()
	if tool == null or commander == null:
		return null
	return commander.technology_mapping.get(tool.type) as TechnologySpec
#endregion
