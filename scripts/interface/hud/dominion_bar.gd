class_name DominionBar
extends EconomyBar

## The persistent, non-text dominion readout, top-left. Reads `Commander.dominion` and the
## same affordability state EconomyBar's colour thresholds are built on
## (ResourcePressure.can_afford_dearest_sanction) — see gdd/systems/ux/ui/economy-bars.md
## §Dominion.
##
## Unlike Energy and Infrastructure, the colour here is three DISCRETE states rather than a
## continuous gradient — pale yellow, then a saturated orange the instant the cheapest
## available sanction is affordable, then a saturated orange-red (oscillating) the instant
## the dearest available one is — because that is what the task asked for: a state change at
## each affordability line, not a blend between them.
##
## Hovering a purchase that costs dominion dims a preview of the cost against this bar — see
## EconomyBar._preview_regions() and gdd/systems/ux/ui/economy-bars.md §Hover previews.
##
## The one bar that reads TWO different hover sources: no piece costs dominion to train or
## build (`TechnologySpec.dominion_cost` is 0 everywhere in the current content), because
## dominion is spent entirely through the sanction grid's UNLOCK buttons — a separate
## button-building path from the command grid's (RTSController._build_sanction_button, not
## ButtonSpec), tracked on its own controller field. _preview_cost() checks that first.
##
## The income rate is drawn INSIDE the bar itself — a translucent region picking up where the
## real fill ends, `PROJECTION_SECONDS` of income wide — rather than as a separate widget
## (EnergyBar's RateIndicator boxes). See _rate_regions() and gdd/systems/ux/ui/economy-bars.md
## §Rate projection.
##
## The projection reads `Commander.projected_dominion_rate()`, not the instantaneous
## `dominion_collection_rate()` the "+X.X/s" text still uses. The two agree under the OLD
## indefinite-hold model (a flat "if this held" is a fair predictor when occupancy only ever
## rises), but a sentence-based Compound's occupancy DECAYS as terms complete — so "if this
## rate held" would overstate the next minute whenever arrivals lag consumption.
## `projected_dominion_rate()` answers a different question instead: what the commander's
## currently-TASKED trucks would sustain, derived from live tasking rather than history. See
## gdd/systems/combat/colonial-dominion.md §A captive serves a sentence.

#region Constants
const PALE_YELLOW: Color = Color(0.93, 0.88, 0.62)
const SATURATED_ORANGE: Color = Color(0.92, 0.55, 0.12)
const SATURATED_ORANGE_RED: Color = Color(0.88, 0.30, 0.14)

## Visual full scale when the grid has nothing available yet (dearest_available_cost() is
## -1) — every tier locked, or nothing on the board at all. A placeholder worth tuning once a
## faction with a locked opening tier is actually played against this bar.
const DEFAULT_VISUAL_SCALE: float = 500.0

## How far ahead the income-rate region projects — "if this rate held for the next minute".
const PROJECTION_SECONDS: float = 60.0
#endregion

func _ready() -> void:
	bar_width = 208.0
	super._ready()

func _current_value() -> float:
	return float(commander.dominion)

## The drawing scale: the affordability threshold, unless a hovered purchase costs more than
## it — in which case the bar grows to fit the preview rather than clipping it (see
## _preview_regions() on the base class).
func _capacity() -> float:
	var dearest: int = _dearest_available_cost()
	var scale: float = float(dearest) if dearest >= 0 else DEFAULT_VISUAL_SCALE
	return maxf(scale, _preview_cost())

func _fill_color(_a_frac: float) -> Color:
	if ResourcePressure.can_afford_dearest_sanction(commander):
		return ResourcePressure.pulse_between(SATURATED_ORANGE_RED,
			SATURATED_ORANGE_RED.lightened(0.4))
	if ResourcePressure.can_afford_cheapest_sanction(commander):
		return SATURATED_ORANGE
	return PALE_YELLOW

## A translucent region picking up exactly where the real fill ends, PROJECTION_SECONDS of
## `projected_dominion_rate()` wide — "if my tasked trucks keep working at this distance,
## here is how much further you'd be", not a flat hold of the current instant. Same colour
## the real fill is drawn in (so it reads as a continuation of the same bar, not a foreign
## indicator), at RATE_BAR_ALPHA. Clamped to the bar's own scale rather than growing it — a
## very high income rate fills the rest of the bar and stops there, it does not rescale the
## whole bar the way an expensive hover preview does.
##
## Past it, what ordered-but-unfinished generators would add over the same minute, in
## PendingStyle. TODO: a NEGATIVE pending change (a planned building over paying Opticon ground)
## draws nothing here — the build preview's claim layer is where that loss shows today.
func _rate_regions() -> Array[Dictionary]:
	var rate: float = maxf(commander.projected_dominion_rate(), 0.0)
	var pending: float = maxf(commander.pending_dominion_collection_rate(), 0.0)
	if rate + pending <= 0.0:
		return []
	var capacity: float = maxf(_capacity(), 0.0001)
	var value: float = _current_value()
	var start_frac: float = clampf(value / capacity, 0.0, 1.0)
	var rate_frac: float = clampf((value + rate * PROJECTION_SECONDS) / capacity, 0.0, 1.0)
	var pending_frac: float = clampf(
		(value + (rate + pending) * PROJECTION_SECONDS) / capacity, 0.0, 1.0)
	var color: Color = _fill_color(start_frac)
	var regions: Array[Dictionary] = []
	if rate_frac > start_frac:
		regions.append({"start_frac": start_frac, "end_frac": rate_frac,
			"color": _at_alpha(color, RATE_BAR_ALPHA)})
	if pending_frac > rate_frac:
		regions.append({"start_frac": rate_frac, "end_frac": pending_frac,
			"color": _at_alpha(color, RATE_BAR_ALPHA * PendingStyle.ALPHA)})
	return regions

func _preview_cost() -> float:
	if controller != null and controller.hovered_sanction_unlock != null:
		var unlock: SanctionUnlock = controller.hovered_sanction_unlock.unlock
		if unlock != null:
			return float(unlock.dominion_cost)
	var spec: TechnologySpec = _hovered_spec()
	return float(spec.dominion_cost) if spec != null else 0.0

func _value_text() -> String:
	return str(commander.dominion)

func _has_verbose_text() -> bool:
	return commander.dominion_collection_rate() > 0.0 or commander.dominion_source_count() > 0

func _verbose_text() -> String:
	var text: String = "+%.1f/s" % commander.dominion_collection_rate()
	var contributors: int = commander.dominion_contributor_count()
	if contributors != DominionGenerator.NO_ATTRIBUTION:
		text += "  ·  %d feeding" % contributors
	return text

func _dearest_available_cost() -> int:
	if commander.sanction_grid == null:
		return -1
	return commander.sanction_grid.dearest_available_cost()
