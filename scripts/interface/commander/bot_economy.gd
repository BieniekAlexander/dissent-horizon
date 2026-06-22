class_name BotEconomy
extends RefCounted

## BotEconomy — grows income and production capacity.
##
## Each think pass, with a free builder available:
##   1. Claim a free Deposit by building a Mine (more ore income), then
##   2. When income is outpacing spending, build another Redoubt (more unit
##      production throughput — see _has_resource_surplus).
## One builder serializes the work, which naturally rate-limits construction.
##
## The surplus test is deliberately simple and isolated in _has_resource_surplus()
## so difficulty settings can later make it smarter (e.g. true income-vs-spend
## rate tracking, target building counts, scouting-gated expansion).

const REDOUBT_TYPE: Entity.Type = Entity.Type.AN_STRUCTURE_REDOUBT
const MINE_TYPE: Entity.Type = Entity.Type.NT_STRUCTURE_MINE

## Ore we want banked before committing to extra production capacity. Sitting
## above this (and not falling) means production isn't draining our income.
const REDOUBT_RESERVE: int = 600

## Ring radii (in cells, around the base centroid) searched for a redoubt spot.
const SEARCH_MIN_RING: int = 2
const SEARCH_MAX_RING: int = 14

var _bot: Bot
var _act: BotActuator
var _prev_ore: int = 0


func _init(a_bot: Bot, a_act: BotActuator) -> void:
	_bot = a_bot
	_act = a_act
	_prev_ore = a_bot.ore


func tick() -> void:
	var surplus: bool = _has_resource_surplus()
	_prev_ore = _bot.ore

	# One construction job at a time — wait for the current builder to finish so
	# we don't pull a second fighter off the line or race two builds onto the same
	# cells. (Difficulty settings can later raise this concurrency.)
	if _someone_constructing():
		return

	var builder: Commandable = _pick_builder()
	if builder == null:
		return

	# When income is outpacing spending, sink the surplus into more production
	# capacity. Redoubts go up near the base, so the build completes reliably.
	if surplus and _bot.can_afford(REDOUBT_TYPE):
		var spot: Variant = _find_build_spot(REDOUBT_TYPE)
		if spot != null:
			_act.build(builder, REDOUBT_TYPE, spot)
			return

	# Otherwise, if we're NOT swimming in ore, grow income by claiming a free
	# deposit with a mine. (When already in surplus we don't need more mines.)
	if not surplus:
		var deposit: Entity = _nearest_unclaimed_deposit()
		if deposit != null and _bot.can_afford(MINE_TYPE):
			_act.build(builder, MINE_TYPE, deposit.global_position)


## Are we earning faster than we spend? Simple proxy (overridable seam for
## difficulty tuning): ore is parked above a healthy reserve AND isn't falling,
## i.e. production training each tick still can't drain what the mines bring in.
func _has_resource_surplus() -> bool:
	return _bot.ore >= REDOUBT_RESERVE and _bot.ore >= _prev_ore


## True while any owned unit is in the middle of constructing (placing or
## repairing-to-complete a structure). Used to serialize builds and to keep the
## military from yanking the active builder back into the fight.
func _someone_constructing() -> bool:
	for u: Commandable in _bot.get_units():
		if _is_constructing(u):
			return true
	return false


static func _is_constructing(u: Commandable) -> bool:
	if not u.has_command():
		return false
	var c: Command = u.current_command()
	return c is Build or c is Repair


## Choose a unit to construct with. Build-capable units (Warlords) are also
## fighters in this faction, which is intended — so we only ever pull ONE, and
## prefer an idle one to minimise disrupting the army; if none is idle we pull a
## fighter (it rejoins combat once the structure is finished). Returns null when
## the bot owns no builder yet (e.g. an all-Irregular army).
func _pick_builder() -> Commandable:
	var busy_builder: Commandable = null
	for u: Commandable in _bot.get_units():
		if not u.has_node("Builds"):
			continue
		if not u.has_command():
			return u  # idle builder — ideal
		busy_builder = u
	return busy_builder


## Closest deposit with no mine on it yet, or null if all are claimed.
func _nearest_unclaimed_deposit() -> Entity:
	var base: Vector3 = _bot.base_centroid()
	var best: Entity = null
	var best_d: float = INF
	for n: Node in _bot.get_tree().get_nodes_in_group("deposit"):
		var dep: Entity = n as Entity
		if dep == null or dep.get("mine") != null:
			continue
		var d: float = base.distance_squared_to(dep.global_position)
		if d < best_d:
			best_d = d
			best = dep
	return best


## Nearest valid, empty, flat footprint to the base centroid for `type`, searched
## ring by ring outward. Returns a world position or null if none found.
func _find_build_spot(type: Entity.Type) -> Variant:
	var dims: Vector2i = _dims_for_type(type)
	var origin: Vector2i = _bot.map.world_to_grid(VU.inXZ(_bot.base_centroid()))
	for radius: int in range(SEARCH_MIN_RING, SEARCH_MAX_RING):
		for dx: int in range(-radius, radius + 1):
			for dy: int in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue  # ring perimeter only
				var world: Vector3 = _bot.map.grid_to_world(Vector2i(origin.x + dx, origin.y + dy))
				if _placement_ok(world, dims):
					return world
	return null


func _placement_ok(world: Vector3, dims: Vector2i) -> bool:
	if not Structure.valid_placement(CommandMessage.new(_bot.map, null, null, world), dims, false):
		return false
	# Never let the bot wall off part of the map: reject any footprint that would
	# split the passable surface, which can strand units (including this builder)
	# in a pocket they can't path out of.
	var footprint: Array = _bot.map.footprint_cells(VU.inXZ(world), dims)
	return _bot.map.terrain_grid.placement_preserves_connectivity(footprint)


## Footprint dimensions for a buildable type, read off its build-preview instance
## (the same Structure component Build inspects). Falls back to 2×2.
func _dims_for_type(type: Entity.Type) -> Vector2i:
	var tool: Tool = Tool.for_type(type)
	if tool != null:
		var preview: Node = _bot.get_build_preview_instance(tool)
		var s: Structure = preview.get_node_or_null("Structure") as Structure if preview != null else null
		if s != null:
			return s.dimensions
	return Vector2i(2, 2)
