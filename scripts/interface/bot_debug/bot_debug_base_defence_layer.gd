class_name BotDebugBaseDefenceLayer
extends BotDebugLayer

## BASE DEFENCE: what the bot believes threatens its base, how safe that leaves it, and where a
## static defence is wanted.
##
## Each base threat: a line from the enemy to the structure it threatens, red, brighter the more
## it is worth, with a ring on the enemy. The base centroid: a white square, with a yellow line
## along the believed threat direction. Each static-defence region (the ground within
## BotEconomy.DEFENCE_REGION_RADIUS of a built structure that anything contests): a ring, blue →
## magenta as its demand nears the price of the cheapest turret, and a stick that height.

const THREAT_RING_RADIUS: float = 0.8
const COLOR_THREAT: Color = Color(1.0, 0.15, 0.15)
## A threat's alpha at the least and the most valuable threat in view.
const THREAT_ALPHA_MIN: float = 0.35
const THREAT_ALPHA_MAX: float = 1.0
const CENTROID_HALF: float = 0.6
const COLOR_CENTROID: Color = Color(1.0, 1.0, 1.0)
const DIRECTION_LENGTH: float = 8.0
const COLOR_DIRECTION: Color = Color(1.0, 0.85, 0.2)
const COLOR_REGION_QUIET: Color = Color(0.3, 0.7, 1.0, 0.4)
const COLOR_REGION_DEMANDING: Color = Color(1.0, 0.25, 0.9, 1.0)
## A region's stick at full demand (the turret's price, after propensity).
const DEMAND_STICK_MAX: float = 4.0


func draw(a_bot: Bot, a_pen: BotDebugPen) -> void:
	var economy: BotEconomy = _economy_of(a_bot)
	var radius: float = economy.defend_threat_radius if economy != null else 0.0
	var threats: Array = a_bot.base_threats(radius) if economy != null else []
	var most: float = threats.reduce(
		func(m: float, t: Dictionary) -> float: return maxf(m, t["value"]), 0.0
	)
	for t: Dictionary in threats:
		var color: Color = COLOR_THREAT
		color.a = lerpf(
			THREAT_ALPHA_MIN, THREAT_ALPHA_MAX, t["value"] / most if most > 0.0 else 1.0
		)
		var enemy: Actor = t["enemy"]
		a_pen.ring(enemy.global_position, THREAT_RING_RADIUS, color)
		a_pen.line(enemy.global_position, (t["structure"] as Actor).global_position, color)
	if not a_bot.get_structures().is_empty():
		var centroid: Vector3 = a_bot.home_centroid()
		a_pen.square(centroid, CENTROID_HALF, COLOR_CENTROID)
		var toward: Vector2 = a_bot.threat_direction(VU.in_xz(centroid))
		a_pen.line(centroid, centroid + VU.from_xz(toward) * DIRECTION_LENGTH, COLOR_DIRECTION)
	if economy == null:
		return
	var price: float = turret_price(a_bot)
	for region: Dictionary in demanding_regions(economy):
		var t: float = demand_fraction(region["demand"], economy.defence_propensity, price)
		var color: Color = COLOR_REGION_QUIET.lerp(COLOR_REGION_DEMANDING, t)
		a_pen.ring(region["centre"], BotEconomy.DEFENCE_REGION_RADIUS, color)
		a_pen.stick(region["centre"], DEMAND_STICK_MAX * t, color)


func readout(a_bot: Bot) -> PackedStringArray:
	var economy: BotEconomy = _economy_of(a_bot)
	if economy == null:
		return PackedStringArray(["no economy manager yet"])
	var terms: Dictionary = economy.safety_terms()
	var threats: Array = a_bot.base_threats(economy.defend_threat_radius)
	var threat_value: float = threats.reduce(
		func(sum: float, t: Dictionary) -> float: return sum + t["value"], 0.0
	)
	var lines: PackedStringArray = PackedStringArray(
		[
			(
				"safety %.2f — under attack: %s, outgunned ×%.2f, bleeding ×%.2f"
				% [
					economy.safety(),
					"yes" if terms["under_attack"] else "no",
					terms["outgunned"],
					terms["bleeding"]
				]
			),
			(
				"income structures wanted: %d, %d after safety"
				% [economy.income_structure_target, economy.effective_income_target()]
			),
			"base threats: %d, worth %d energy" % [threats.size(), roundi(threat_value)],
		]
	)
	var regions: Array = demanding_regions(economy)
	regions.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return a["demand"] > b["demand"]
	)
	var price: float = turret_price(a_bot)
	lines.append(
		(
			"defence demand (turret %d, propensity ×%.2f):"
			% [roundi(price), economy.defence_propensity]
		)
	)
	if regions.is_empty():
		lines.append("  no region wants a turret")
	for region: Dictionary in regions:
		lines.append(
			(
				"  %d = value %d × contest (own %d, enemy %d)"
				% [
					roundi(region["demand"]),
					roundi(region["value"]),
					roundi(region["own"]),
					roundi(region["enemy"])
				]
			)
		)
	return lines


## The regions asking for a turret at all. One only our side or only theirs stands in has
## tension and no demand, and would bury the ones that do.
static func demanding_regions(economy: BotEconomy) -> Array:
	return economy.defence_demand_by_region().filter(
		func(r: Dictionary) -> bool: return float(r["demand"]) > 0.0
	)


## What the cheapest buildable static defence costs: the bar a region's demand must clear. 0 for
## a bot that can build none.
static func turret_price(bot: Bot) -> float:
	var costs: Array = bot.buildable_defence_structure_types().map(
		func(t: Variant) -> int: return bot.unit_cost(t)
	)
	return float(costs.min()) if not costs.is_empty() else 0.0


## How far `demand`, scaled by `propensity`, goes toward `price`: 0 → 1, and 1 at or past it.
static func demand_fraction(demand: float, propensity: float, price: float) -> float:
	if price <= 0.0:
		return 1.0 if demand > 0.0 else 0.0
	return clampf(demand * propensity / price, 0.0, 1.0)


static func _economy_of(bot: Bot) -> BotEconomy:
	var brain: BotBrain = brain_of(bot)
	return brain.get_economy() if brain != null else null
