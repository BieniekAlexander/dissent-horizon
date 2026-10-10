class_name BotIncome
extends RefCounted

## THE ECONOMY SIGNALS: the bot's own income rate, and a FOG-LIMITED ESTIMATE of the enemy's,
## for the `commitment` dial (gdd/systems/ai/objective-selection.md §The economy signals).
## Nothing in the bot sensed income before this, for either side, so booming and all-in —
## responses to being behind or ahead on economy — could only ever have run on a timer.
##
## The enemy's income is A PRIOR THAT OBSERVATION REPLACES PIECEWISE (decided 2026-10-09,
## over a bare count of what has been seen, which reads "they have nothing" to a bot that
## stayed home): the enemy is assumed to earn `assumed_enemy_income_parity` × the bot's own
## income, the economy twin of `assumed_enemy_parity`; that prior is shared evenly over the
## SHELTER BANDS the enemy could have started in (every shelter but the bot's own — map
## generation places a start's shelter inside a band around it, and the shelters are shown
## from match start); and for each band the share is replaced, as far as the scout grid has
## seen the band freshly, by the income structures the bot believes stand there, priced by
## type (an extractor's rate, a pond's multiple). A believed income structure outside every
## band counts in full. Low variance by construction: the estimate moves with the bot's own
## income and one band at a time, and the gap between a band's prior and its observation is
## what scouting it is worth. On a map with no shelters the prior is scaled by the scout
## grid's stale fraction instead — the same rule with the whole map as the one band.

## The shelter band's radius, in world units: the generator's `shelter_start_band_max_cells`.
## A map does not carry the parameters it was generated with, so the generator's defaults
## stand for every map, a hand-authored one included. TODO: a map that records its params
## would make this exact per map; whether that is worth a field on Map is undecided.
var band_radius: float = (
	float(MapGenerationParams.new().shelter_start_band_max_cells) * Map.CELL_SIZE
)

## The enemy's assumed income as a fraction of the bot's own, where nothing has been scouted.
## A PARAMETER (BotDifficulty.assumed_enemy_income_parity).
var assumed_enemy_income_parity: float = 1.0

var _bot: Bot
## The scout grid, for how freshly a band has been seen; null reads every band as unscouted.
var _scout: BotScout


func _init(a_bot: Bot, a_scout: BotScout) -> void:
	_bot = a_bot
	_scout = a_scout


## Energy per second the bot's own standing extractors pay: the steady rate.
func own_rate() -> float:
	return _bot.energy_collection_rate()


## Energy per second the enemy is estimated to earn — see the file comment.
func enemy_rate_estimate() -> float:
	var terms: Dictionary = self.terms()
	return estimate(terms["prior"], terms["bands"], terms["elsewhere"], terms["stale"])


## The lead in [−1, 1]: own income against the enemy estimate; 0 when neither earns.
func economy_lead() -> float:
	return lead(own_rate(), enemy_rate_estimate())


## The estimate's inputs, each read live: the prior, the bands (centre, coverage, observed
## rate), what is believed outside every band, and the stale fraction the no-shelter rule uses.
func terms() -> Dictionary:
	var shelters: Array = candidate_shelters(_shelter_points(), VU.in_xz(_bot.home_centroid()))
	var apportioned: Dictionary = apportion(shelters, _observations(), band_radius)
	var bands: Array = []
	for band: Dictionary in apportioned["bands"]:
		var coverage: float = (
			_scout.fresh_fraction_within(band["centre"], band_radius) if _scout != null else 0.0
		)
		bands.append({"centre": band["centre"], "coverage": coverage, "observed": band["observed"]})
	return {
		"own": own_rate(),
		"prior": assumed_enemy_income_parity * own_rate(),
		"bands": bands,
		"elsewhere": apportioned["elsewhere"],
		"stale": _scout.stale_fraction() if _scout != null else 1.0,
	}


#region The pure rules
## THE ESTIMATE: each band keeps the unscouted part of its share of the prior and adds what was
## seen there; what was seen outside every band is added whole. With no bands, the prior
## scaled by the stale fraction stands in for the bands.
static func estimate(prior: float, bands: Array, elsewhere: float, stale_fraction: float) -> float:
	if bands.is_empty():
		return prior * stale_fraction + elsewhere
	var share: float = prior / float(bands.size())
	var total: float = elsewhere
	for band: Dictionary in bands:
		total += (1.0 - clampf(float(band["coverage"]), 0.0, 1.0)) * share + float(band["observed"])
	return total


## (own − enemy) / (own + enemy); 0 with nothing on either side.
static func lead(own: float, enemy: float) -> float:
	var total: float = own + enemy
	return (own - enemy) / total if total > 0.0 else 0.0


## Every shelter but the one nearest `home_xz` — the bands the enemy could have started in.
static func candidate_shelters(shelters: Array, home_xz: Vector2) -> Array:
	if shelters.size() < 2:
		return []
	var nearest: int = 0
	for i: int in shelters.size():
		if (
			(shelters[i] as Vector2).distance_squared_to(home_xz)
			< (shelters[nearest] as Vector2).distance_squared_to(home_xz)
		):
			nearest = i
	var out: Array = shelters.duplicate()
	out.remove_at(nearest)
	return out


## Each observation ({ "xz", "rate" }) goes to the nearest shelter within `radius` of it, else
## to `elsewhere`. Returns { "bands": [{ "centre", "observed" }] (one per shelter, in order),
## "elsewhere": float }.
static func apportion(shelters: Array, observations: Array, radius: float) -> Dictionary:
	var bands: Array = []
	for centre: Vector2 in shelters:
		bands.append({"centre": centre, "observed": 0.0})
	var elsewhere: float = 0.0
	for observation: Dictionary in observations:
		var xz: Vector2 = observation["xz"]
		var best: int = -1
		var best_distance: float = radius * radius
		for i: int in shelters.size():
			var distance: float = (shelters[i] as Vector2).distance_squared_to(xz)
			if distance <= best_distance:
				best_distance = distance
				best = i
		if best < 0:
			elsewhere += float(observation["rate"])
		else:
			bands[best]["observed"] += float(observation["rate"])
	return {"bands": bands, "elsewhere": elsewhere}


#endregion


## Where every shelter on the map stands; none outside a scene.
func _shelter_points() -> Array:
	if not _bot.is_inside_tree():
		return []
	return Array(Scenario.shelter_points(_bot.get_tree()))


## Every believed enemy structure that earns, as { "xz", "rate" }: priced by its type, and by
## the pond's multiple when it stands in one. Fog-limited like every belief.
func _observations() -> Array:
	var out: Array = []
	if _bot.blackboard == null:
		return out
	for entry: CommanderBlackboard.Entry in _bot.blackboard.believed_structures():
		var rate: float = _bot.income_rate_of_type(entry.type)
		if rate <= 0.0:
			continue
		var xz: Vector2 = VU.in_xz(entry.last_known_location)
		if _bot.map != null and _bot.map.water_body_at(_bot.map.world_to_grid(xz)) != null:
			rate *= float(WaterBody.POND_RATE_MULTIPLIER)
		out.append({"xz": xz, "rate": rate})
	return out
