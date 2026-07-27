class_name EnergyBar
extends EconomyBar

## The persistent, non-text energy readout above the command card — stacked above
## InfrastructureBar. Reads `Commander.energy`, `energy_collection_rate`, `energy_spend_rate`
## directly. Full write-up: gdd/systems/ux/ui/economy-bars.md §Energy.
##
## The fill is scaled against ResourcePressure.ENERGY_SURPLUS_THRESHOLD, and painted as a
## SINGLE flat colour — chosen from where the fill currently sits on a three-stop
## lithium-pond gradient, not painted as a ramp across the fill itself (gdd/tasks.md
## "UI Updates"). Past the threshold the fill oscillates toward a lightened version of
## itself, the "state you should act on now" idiom every bar in this family uses.
##
## Hovering a purchase that costs energy dims a preview of the cost against this bar — see
## EconomyBar._preview_regions() and gdd/systems/ux/ui/economy-bars.md §Hover previews. Energy
## queued purchases have promised, and the rate pending extractors will add, are drawn as
## pending (§Pending pieces).
##
## TODO: the consumption-rate indicator shows Commander.energy_spend_rate() alone — the
## "fallback vs. non-fallback queued commitments" split the task asked for is not resolved;
## see gdd/tasks.md "UI Updates" §the open question and gdd/systems/ux/ui/economy-bars.md
## §Energy consumption is one rate, not two (yet).

#region Constants
## Tiffany blue → seafoam green → canary gold, the visual progression from a lithium pond at
## low concentration to high (gdd/tasks.md "UI Updates"). A real Gradient, the same idiom
## HealthBarGradient holds its HP ramp in, rather than a hand-rolled lerp — see BarGradient.
## Picked as ordinary reference values for those three named colours; with_saturation_ramp is
## what does the "increase in saturation" the task asked for, not these on their own.
static var _gradient: Gradient = _build_gradient()

static func _build_gradient() -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([
		Color(0.039, 0.729, 0.710),  # tiffany blue
		Color(0.624, 0.886, 0.749),  # seafoam green
		Color(0.96, 0.80, 0.25),     # canary gold
	])
	return g

## The energy-per-second full scale for the rate indicator's two mini-bars. No existing
## constant answers "what counts as a fast rate" — this is a placeholder worth tuning against
## real matches, same footing as the difficulty ramp's numbers.
const RATE_VISUAL_SCALE: float = 50.0
const PRODUCTION_COLOR: Color = Color(0.54, 0.80, 0.40)
const CONSUMPTION_COLOR: Color = Color(0.86, 0.55, 0.30)
#endregion

var _rate_indicator: RateIndicator

func _ready() -> void:
	bar_width = 208.0
	super._ready()
	_rate_indicator = RateIndicator.new()
	_rate_indicator.height = BAR_HEIGHT
	_rate_indicator.position = Vector2(bar_width + LABEL_GUTTER + 60.0, 0.0)
	add_child(_rate_indicator)

func refresh() -> void:
	super.refresh()
	if commander == null or _rate_indicator == null:
		return
	_rate_indicator.bars = [
		{"color": PRODUCTION_COLOR, "value": commander.energy_collection_rate(),
			"pending": commander.pending_energy_collection_rate(), "scale": RATE_VISUAL_SCALE},
		{"color": CONSUMPTION_COLOR, "value": commander.energy_spend_rate(),
			"scale": RATE_VISUAL_SCALE},
	]
	_rate_indicator.queue_redraw()

func _current_value() -> float:
	return float(commander.energy)

## The drawing scale: the real threshold, unless a hovered purchase costs more than it — in
## which case the bar grows to fit the preview rather than clipping it (see
## _preview_regions() on the base class). The OSCILLATION trigger in _fill_color() below
## checks the real threshold directly instead, so hovering something expensive cannot
## silently stop a genuinely-over-threshold bar from pulsing.
func _capacity() -> float:
	return maxf(float(ResourcePressure.ENERGY_SURPLUS_THRESHOLD), _preview_cost())

## The fill, with the slice queued purchases have already spoken for drawn in PendingStyle at
## its right end: that energy is banked but promised (Commander.energy_committed), so it reads as
## "yours, not for long". Past the whole fill when the queue owes more than is banked.
func _fill_regions() -> Array[Dictionary]:
	var capacity: float = maxf(_capacity(), 0.0001)
	var value: float = _current_value()
	var frac: float = clampf(value / capacity, 0.0, 1.0)
	if frac <= 0.0:
		return []
	var color: Color = _fill_color(frac)
	var free_frac: float = clampf((value - float(commander.energy_committed())) / capacity,
		0.0, frac)
	var regions: Array[Dictionary] = []
	if free_frac > 0.0:
		regions.append({"start_frac": 0.0, "end_frac": free_frac, "color": color})
	if frac > free_frac:
		regions.append({"start_frac": free_frac, "end_frac": frac, "color": PendingStyle.of(color)})
	return regions

func _fill_color(a_frac: float) -> Color:
	var base: Color = BarGradient.with_saturation_ramp(_gradient.sample(a_frac), a_frac)
	if commander.energy > ResourcePressure.ENERGY_SURPLUS_THRESHOLD:
		return ResourcePressure.pulse_between(base, base.lightened(0.5))
	return base

func _preview_cost() -> float:
	var spec: TechnologySpec = _hovered_spec()
	return float(spec.energy_cost) if spec != null else 0.0

func _value_text() -> String:
	return str(commander.energy)

func _has_verbose_text() -> bool:
	return true

func _verbose_text() -> String:
	return "+%.1f/s  −%.1f/s  ·  %d extractors" % [
		commander.energy_collection_rate(),
		commander.energy_spend_rate(),
		commander.energy_source_count(),
	]
