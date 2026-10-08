class_name InfrastructureBar
extends EconomyBar

## The persistent, non-text infrastructure readout directly above the command card, stacked
## below EnergyBar. Same source of truth as
## `Commander.infrastructure_required`/`infrastructure_provided`, and
## the same pressure vocabulary `ResourcePressure` already carries for the "approaching /
## over capacity" states. See gdd/systems/ux/ui/economy-bars.md §Infrastructure.
##
## Unlike Energy and Dominion, the fill is not a single growing region — the bar's two
## regions TOGETHER always cover its whole width:
##   - USED, left, light orange: `min(required, provided)`.
##   - the remainder, right: light grey when there is spare capacity (`provided > required`),
##     dark orange when upkeep has run past it (`required > provided`) — the "approaching /
##     over" states apply to THIS region, since it is the one whose meaning changes.
## The bar's own length is `max(required, provided)` (economy-bars.md §Infrastructure), so the
## boundary between the two regions marks capacity directly — no separate marker line needed.
##
## Hovering a purchase previews its `Actor.infrastructure` export (read off
## `Commander.get_build_preview_instance` — see CLAUDE.md §Things NOT to break for why that
## instance must never enter the SceneTree), dimmed, on TOP of the real regions. Unlike
## Energy/Dominion there is no afford/can't-afford split — infrastructure never blocks a
## purchase (CLAUDE.md, `Commander.is_deferrable_need`), so the preview always shows the same
## shape regardless of whether the commander could actually pay for it.

#region Constants
## The bar's default visual full scale. Below this, capacity is a small commitment and the
## bar reads mostly empty; a commander using or providing more than this rescales the bar
## rather than overflowing it.
const DEFAULT_VISUAL_THRESHOLD: float = 500.0

const USED_COLOR: Color = Color(0.94, 0.72, 0.42)  # light orange
const SPARE_COLOR: Color = Color(0.72, 0.72, 0.72)  # light grey
#endregion


func _ready() -> void:
	bar_width = 208.0
	super._ready()


func _current_value() -> float:
	return float(commander.infrastructure_required)


## The drawing scale: real usage/capacity, floored at DEFAULT_VISUAL_THRESHOLD, widened
## further when a hovered purchase's preview would otherwise run past the bar's right edge —
## the same "grow to fit rather than clip" rule EnergyBar and DominionBar apply to their own
## previews.
func _capacity() -> float:
	var required: float = float(commander.infrastructure_required)
	var provided: float = float(commander.infrastructure_provided)
	var scale: float = maxf(DEFAULT_VISUAL_THRESHOLD, maxf(required, provided))
	scale = maxf(
		scale,
		maxf(
			required + float(commander.pending_infrastructure_required()),
			provided + float(commander.pending_infrastructure_provided())
		)
	)
	var delta: int = _hovered_infrastructure_delta()
	if delta > 0:
		scale = maxf(scale, provided + float(delta))
	elif delta < 0:
		scale = maxf(scale, required + absf(float(delta)))
	return scale


func _fill_regions() -> Array[Dictionary]:
	var required: float = float(commander.infrastructure_required)
	var provided: float = float(commander.infrastructure_provided)
	var capacity: float = _capacity()
	var used: float = minf(required, provided)
	var edge: float = maxf(required, provided)
	var regions: Array[Dictionary] = []
	if used > 0.0:
		regions.append(_region(0.0, used, capacity, USED_COLOR))
	if edge > used:
		regions.append(_region(used, edge, capacity, _excess_color(required, provided)))
	for segment: Array in projected_changes(
		required,
		provided,
		required + float(commander.pending_infrastructure_required()),
		provided + float(commander.pending_infrastructure_provided())
	):
		regions.append(
			_region(segment[0], segment[1], capacity, PendingStyle.of(_band_color(segment[2])))
		)
	return regions


## What the bar's picture is at any point along it: nothing, used, spare or over capacity.
enum Band { NONE, USED, SPARE, OVER }


## Where the picture ordered-but-unfinished pieces will leave differs from today's, as
## [start, end, Band] in infrastructure units: the future band over each stretch whose band
## changes. That is what InfrastructureBar draws as pending — upkeep eating into spare
## capacity, capacity arriving, a deficit an order will open or close. Pure, for tests.
static func projected_changes(
	required: float, provided: float, future_required: float, future_provided: float
) -> Array:
	var cuts: Array = [
		0.0,
		minf(required, provided),
		maxf(required, provided),
		minf(future_required, future_provided),
		maxf(future_required, future_provided)
	]
	cuts.sort()
	var out: Array = []
	for i: int in cuts.size() - 1:
		var start: float = cuts[i]
		var end: float = cuts[i + 1]
		if end <= start:
			continue
		var middle: float = 0.5 * (start + end)
		var future: Band = band_at(middle, future_required, future_provided)
		if future != Band.NONE and future != band_at(middle, required, provided):
			out.append([start, end, future])
	return out


## The band at `x` along a bar showing `required` against `provided`.
static func band_at(x: float, required: float, provided: float) -> Band:
	if x < minf(required, provided):
		return Band.USED
	if x < provided:
		return Band.SPARE
	if x < required:
		return Band.OVER
	return Band.NONE


## A band's colour, STEADY: pending is a state that has not happened, so it never pulses.
func _band_color(a_band: Band) -> Color:
	match a_band:
		Band.USED:
			return USED_COLOR
		Band.OVER:
			return ResourcePressure.INFRASTRUCTURE_OVER_COLOR
	return SPARE_COLOR


## The region past `min(required, provided)`: spare capacity (grey) or overdrawn upkeep
## (orange), carrying the same "approaching / over" states the resource card used to pulse —
## steady past ResourcePressure.INFRASTRUCTURE_PRESSURE_FRACTION, pulsing once truly strained.
## The pulse is SELF-REFERENTIAL (toward a lightened version of its own colour) rather than
## toward white, so the flash reads as "this colour, brighter" rather than blowing out to a
## colour that means nothing on this bar.
func _excess_color(a_required: float, a_provided: float) -> Color:
	if a_required > a_provided:
		return ResourcePressure.pulse_between(
			ResourcePressure.INFRASTRUCTURE_OVER_COLOR,
			ResourcePressure.INFRASTRUCTURE_OVER_COLOR.lightened(0.4)
		)
	if (
		a_provided > 0.0
		and a_required / a_provided >= ResourcePressure.INFRASTRUCTURE_PRESSURE_FRACTION
	):
		return ResourcePressure.INFRASTRUCTURE_PRESSURE_COLOR
	return SPARE_COLOR


func _segment_size() -> float:
	return float(commander.infrastructure_provider_grant())


func _value_text() -> String:
	return "%d/%d" % [commander.infrastructure_required, commander.infrastructure_provided]


func _has_verbose_text() -> bool:
	return true


func _verbose_text() -> String:
	var grant: int = commander.infrastructure_provider_grant()
	var text: String = "spare %d" % commander.infrastructure
	if grant > 0:
		text += "  ·  %d/provider" % grant
	var ordered_provided: int = commander.pending_infrastructure_provided()
	var ordered_required: int = commander.pending_infrastructure_required()
	if ordered_provided != 0 or ordered_required != 0:
		text += "  ·  ordered +%d −%d" % [ordered_provided, ordered_required]
	return text


## The hovered purchase's own ongoing `Actor.infrastructure` contribution once built —
## positive provides, negative consumes, 0 (the default) when nothing relevant is hovered.
## Read off the cached out-of-tree preview instance rather than TechnologySpec, which does
## not carry this figure at all (see the class comment above).
func _hovered_infrastructure_delta() -> int:
	var tool: Tool = _previewed_tool()
	if tool == null or commander == null:
		return 0
	var preview: Actor = commander.get_build_preview_instance(tool) as Actor
	return preview.infrastructure if preview != null else 0


## Providing MORE (`delta > 0`): a dim SPARE_COLOR block appended past the bar's current right
## edge, `delta` wide — literally "how much more infrastructure I will have".
##
## Consuming MORE (`delta < 0`): the increment is split at the bar's CURRENT right edge (the
## boundary where a real deficit would begin) — the part that still fits inside existing spare
## capacity previews as dim USED_COLOR, and any part past it previews as the dim "deficit"
## colour, STEADY rather than pulsing per the task: the oscillation is a statement about a
## REAL state, and hovering has not made this one real yet.
func _preview_regions() -> Array[Dictionary]:
	var delta: int = _hovered_infrastructure_delta()
	if delta == 0:
		return []
	var capacity: float = _capacity()
	var required: float = float(commander.infrastructure_required)
	var provided: float = float(commander.infrastructure_provided)
	var edge: float = maxf(required, provided)
	var regions: Array[Dictionary] = []
	if delta > 0:
		regions.append(_region(edge, edge + float(delta), capacity, _dimmed(SPARE_COLOR)))
		return regions
	var new_required: float = required + absf(float(delta))
	var deficit_split: float = minf(new_required, edge)
	if deficit_split > required:
		regions.append(_region(required, deficit_split, capacity, _dimmed(USED_COLOR)))
	if new_required > edge:
		regions.append(
			_region(
				edge, new_required, capacity, _dimmed(ResourcePressure.INFRASTRUCTURE_OVER_COLOR)
			)
		)
	return regions


func _region(a_start: float, a_end: float, a_capacity: float, a_color: Color) -> Dictionary:
	return {
		"start_frac": clampf(a_start / a_capacity, 0.0, 1.0),
		"end_frac": clampf(a_end / a_capacity, 0.0, 1.0),
		"color": a_color,
	}
