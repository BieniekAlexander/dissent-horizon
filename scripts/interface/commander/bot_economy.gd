class_name BotEconomy
extends RefCounted

## BotEconomy — grows income and production capacity.
##
## Each think pass, with a free builder available:
##   1. When income is outpacing spending, build a production structure (more unit
##      throughput — see _has_resource_surplus), else
##   2. Grow income by building a mine on a free Deposit.
## One builder serializes the work, which naturally rate-limits construction.
##
## WHICH structures it builds is NOT hardcoded — it's derived from the bot's
## buildable set (registry ∩ builder capabilities ∩ tech) classified by component
## (Production / OreExtractor). A newly-added buildable structure (e.g. a Hangar) is
## picked up automatically; see Bot.buildable_production_structure_types / _income_.
##
## The surplus test is deliberately simple and isolated in _has_resource_surplus()
## so difficulty settings can later make it smarter (e.g. true income-vs-spend
## rate tracking, target building counts, scouting-gated expansion).

## Ore we want banked before committing to extra production capacity. Sitting
## above this (and not falling) means production isn't draining our income.
const STRONGHOLD_RESERVE: int = 600

## Ring radii (in cells, around the base centroid) searched for a stronghold spot.
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

	# Priority: stand up the faction's dominion structure (e.g. the internment camp)
	# if we don't own one yet — it anchors the dominion strategy the opportunist's
	# capture/deposit loop feeds. Detected generically by the DominionGenerator
	# component, so future faction dominion buildings are picked up automatically.
	var dtype: Variant = _dominion_structure_to_build()
	if dtype != null:
		var dspot: Variant = _find_build_spot(dtype)
		if dspot != null:
			_act.build(builder, dtype, dspot)
		return

	# Before expanding further, make sure there's vigor headroom: if we're low on
	# spare capacity, stand up the faction's vigor provider (power plant / safehouse /
	# dwelling) first. While one is needed we don't add more buildings — if it's not
	# affordable yet we bank for it rather than digging the strain deeper.
	if _bot.needs_vigor_provider():
		var vtype: Variant = _vigor_structure_to_build()
		if vtype != null:
			if _bot.can_afford(vtype):
				var vspot: Variant = _find_build_spot(vtype)
				if vspot != null:
					_act.build(builder, vtype, vspot)
			return

	# When income is outpacing spending, sink the surplus into more production
	# capacity. Built near the base, so the build completes reliably.
	if surplus:
		var ptype: Variant = _production_structure_to_build()
		if ptype != null:
			var spot: Variant = _find_build_spot(ptype)
			if spot != null:
				_act.build(builder, ptype, spot)
		return

	# Otherwise, if we're NOT swimming in ore, grow income by claiming a free
	# deposit with a mine. (When already in surplus we don't need more mines.)
	var mtype: Variant = _income_structure_to_build()
	if mtype != null:
		var deposit: Entity = _nearest_unclaimed_deposit()
		if deposit != null:
			_act.build(builder, mtype, deposit.global_position)


## Which production structure to build now: an affordable buildable production
## type, PREFERRING one we don't own yet — so every production building (e.g. a
## newly-added Hangar) gets built at least once to unlock its units, before scaling
## up the cheapest existing one. null when none is affordable.
func _production_structure_to_build() -> Variant:
	var candidates: Array = _bot.buildable_production_structure_types().filter(
		func(t): return _bot.can_afford(t)
	)
	if candidates.is_empty():
		return null
	var unowned: Array = candidates.filter(
		func(t): return _bot.get_structures_of_type(t).is_empty()
	)
	var pool: Array = unowned if not unowned.is_empty() else candidates
	pool.sort_custom(func(a, b): return _ore_cost(a) < _ore_cost(b))
	return pool[0]


## Cheapest affordable buildable dominion structure we don't own yet (currently the
## internment camp), or null. We only stand up one — extra capacity is handled by the
## capture loop filling it, not by building more.
func _dominion_structure_to_build() -> Variant:
	var candidates: Array = _bot.buildable_dominion_structure_types().filter(
		func(t): return _bot.can_afford(t) and _bot.get_structures_of_type(t).is_empty()
	)
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(a, b): return _ore_cost(a) < _ore_cost(b))
	return candidates[0]


## Cheapest buildable vigor provider (tech-available), regardless of affordability so
## the caller can bank for it. null when the faction has none in its buildable set.
func _vigor_structure_to_build() -> Variant:
	var candidates: Array = _bot.buildable_vigor_structure_types()
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(a, b): return _ore_cost(a) < _ore_cost(b))
	return candidates[0]


## Cheapest affordable buildable income (mine) structure, or null.
func _income_structure_to_build() -> Variant:
	var candidates: Array = _bot.buildable_income_structure_types().filter(
		func(t): return _bot.can_afford(t)
	)
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(a, b): return _ore_cost(a) < _ore_cost(b))
	return candidates[0]


func _ore_cost(type) -> int:
	var spec: TechnologySpec = _bot.technology_mapping.get(type)
	return spec.ore_cost if spec != null else 0


## Are we earning faster than we spend? Simple proxy (overridable seam for
## difficulty tuning): ore is parked above a healthy reserve AND isn't falling,
## i.e. production training each tick still can't drain what the mines bring in.
func _has_resource_surplus() -> bool:
	return _bot.ore >= STRONGHOLD_RESERVE and _bot.ore >= _prev_ore


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
	var c: MoveCommand = u.current_command()
	return c is Build or c is Repair


## Choose a unit to construct with. Build-capable units (Irregulars) are also
## fighters in this faction, which is intended — so we only ever pull ONE, and
## prefer an idle one to minimise disrupting the army; if none is idle we pull a
## fighter (it rejoins combat once the structure is finished). Returns null when
## the bot owns no builder yet.
func _pick_builder() -> Commandable:
	var busy_builder: Commandable = null
	for u: Commandable in _bot.get_units():
		if not u.has_node("Builds"):
			continue
		# Don't yank a unit mid-opportunity (e.g. a truck capturing/depositing) onto a
		# build job — that loop is committed work, like construction itself.
		if BotOpportunist.is_committed(u):
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
func _find_build_spot(type: StringName) -> Variant:
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
func _dims_for_type(type: StringName) -> Vector2i:
	var tool: Tool = Tool.for_type(type)
	if tool != null:
		var preview: Node = _bot.get_build_preview_instance(tool)
		var s: Structure = preview.get_node_or_null("Structure") as Structure if preview != null else null
		if s != null:
			return s.dimensions
	return Vector2i(2, 2)
