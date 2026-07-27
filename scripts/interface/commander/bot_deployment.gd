class_name BotDeployment
extends RefCounted

## The bot's side of deferred deployment: where it drops its command centre, and then its two
## extractors. It lands them through Deployment.drop, the same order the player's HUD gives.
##
## THE COMMAND CENTRE: while its units scout, the bot ranks the spots around them with the
## placement score every building it places is chosen by (bot-architecture.md §Where a building
## goes), keeps the best one that may actually take the drop, and drops once that clears a
## threshold. The threshold starts at the best cost the score can give and relaxes linearly to
## the worst by DEADLINE_SECONDS, so by then the best spot seen so far is taken whatever it is.
## A spot ranked around the army is scored against where the army stood at the time, so "best
## seen so far" compares scores from different anchors; each is re-checked before it is used.
##
## THE EXTRACTORS go down as soon as the command centre is in, ranked around it and weighted
## behind it like any support building. Nothing about them waits.

## THE BOT'S OWN DEADLINE, in seconds of match time. The game imposes none (starting-formations.md
## §Deferred deployment); a bot that scouts forever never has an economy.
const DEADLINE_SECONDS: float = 60.0

## Work units per ranked spot checked against the drop rule: one fog lookup per corner up front,
## and the full verdict on the few that pass it.
const SPOT_CHECK_WORK_UNITS: int = 6

var _bot: Bot
var _economy: BotEconomy

## The ranking in progress, or {} — {"drop": Deployment.Drop, "ranking": Dictionary}.
var _search: Dictionary = {}
## The best command-centre spot seen so far and its cost; null before one has been seen.
var _best_xz: Variant = null
var _best_cost: float = INF


func _init(a_bot: Bot, a_economy: BotEconomy) -> void:
	_bot = a_bot
	_economy = a_economy


## True while a ranking is part-way through.
func is_pending() -> bool:
	return not _search.is_empty()


## Carry the deployment on by at most `a_allowance` work units; returns the units spent.
func tick(a_allowance: int = BotJob.UNLIMITED_WORK_UNITS) -> int:
	var deployment: Deployment = _bot.deployment
	if deployment == null or deployment.is_spent():
		return 0
	var drop: Deployment.Drop = Deployment.Drop.COMMAND_CENTRE \
		if deployment.has_charge(Deployment.Drop.COMMAND_CENTRE) else Deployment.Drop.EXTRACTOR
	if _search.is_empty():
		var anchor: Variant = _anchor_for(drop)
		if anchor == null:
			return 0
		_search = {"drop": drop, "ranking": _economy.start_spot_ranking(
			anchor, deployment.footprint_dims(drop), deployment.is_production(drop))}
	var ranking: Dictionary = _search["ranking"]
	var spent: int = _economy.continue_spot_ranking(ranking, a_allowance)
	if not ranking["done"]:
		return spent
	_search = {}
	var found: Array = _first_landable(deployment, drop, ranking["out"])
	spent += int(found[1])
	if found[0] == null:
		return spent
	if drop == Deployment.Drop.EXTRACTOR:
		deployment.drop(drop, found[0])
		return spent
	var cost: float = BotEconomy.ranked_cost(found[2])
	if _best_xz == null or deployment.verdict(drop, _best_xz) != Deployment.Verdict.OK \
			or cost < _best_cost:
		_best_xz = found[0]
		_best_cost = cost
	if _best_cost <= acceptable_cost(_bot.seconds_elapsed(),
			_economy.spot_cost_bounds(deployment.is_production(drop))):
		deployment.drop(drop, _best_xz)
	return spent


## The dearest spot the bot will take `a_elapsed_seconds` into the match: the ideal cost at the
## start, relaxing linearly to the worst the ranking can produce at DEADLINE_SECONDS.
static func acceptable_cost(a_elapsed_seconds: float, a_bounds: Vector2) -> float:
	return lerpf(a_bounds.x, a_bounds.y, clampf(a_elapsed_seconds / DEADLINE_SECONDS, 0.0, 1.0))


## Where a `a_drop` ranking is centred: the army for the command centre, which stands where it
## is scouting; the base for an extractor. Null when there is nothing to centre it on.
func _anchor_for(a_drop: Deployment.Drop) -> Variant:
	if a_drop == Deployment.Drop.EXTRACTOR:
		return VU.inXZ(_bot.base_centroid())
	var units: Array = _bot.get_units()
	if units.is_empty():
		return null
	var sum := Vector2.ZERO
	for unit: Commandable in units:
		sum += VU.inXZ(unit.global_position)
	return sum / float(units.size())


## The first candidate in `a_ranked` the drop may land on, as [world XZ or null, work spent,
## the packed candidate]. The ranking is best-first, so the first that lands is the best one.
func _first_landable(a_deployment: Deployment, a_drop: Deployment.Drop,
		a_ranked: PackedInt64Array) -> Array:
	var map: Map = _bot.map
	var dims: Vector2i = a_deployment.footprint_dims(a_drop)
	var width: int = map.terrain_grid.grid_width()
	var spent: int = 0
	for packed: int in a_ranked:
		spent += SPOT_CHECK_WORK_UNITS
		var origin: Vector2i = BotEconomy.ranked_origin(packed, width)
		# Most of the ring is still unseen while the army scouts; the corners reject those
		# without paying for the full verdict.
		if not _corners_seen(map, origin, dims):
			continue
		var xz: Vector2 = VU.inXZ(map.footprint_centroid(origin, dims))
		if a_deployment.verdict(a_drop, xz) == Deployment.Verdict.OK:
			return [xz, spent, packed]
	return [null, spent, 0]


func _corners_seen(a_map: Map, a_origin: Vector2i, a_dims: Vector2i) -> bool:
	var last: Vector2i = a_origin + a_dims - Vector2i.ONE
	var corners: Array[Vector2i] = [
		a_origin, last, Vector2i(a_origin.x, last.y), Vector2i(last.x, a_origin.y)
	]
	for corner: Vector2i in corners:
		if not _bot.has_vision_at(a_map.grid_to_world(corner)):
			return false
	return true
