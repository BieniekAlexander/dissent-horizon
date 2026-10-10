extends GutTest

## THE UTILITY-UNIT COUNT FOLLOWS THE WORK.
##
## `BotProduction` picks every combat unit by comparison (`unit_composition_value` —
## effectiveness × demand, with cost explicitly not a tiebreaker) and picked utility units by
## a constant: `utility_unit_cap`, 3 per type for every tier including PASSIVE. That constant
## was both floor and ceiling — the bot built a third Stock Truck when three armed units
## would have served it better, and would never build a fourth when the capture loop was the
## best energy on the map.
##
## What replaces it is one utility unit per live errand: a builder per concurrent build job,
## a carrier per capturable cluster, a spare, and two corrections for things that changed
## after the question was written (scouting is where the fog-limited attack objective's
## intelligence comes from, and a crusher counts as army). `utility_unit_cap` survives as the
## ceiling on the answer.
##
## The fixtures answer the TYPE questions directly rather than instantiating real units:
## `Bot.unit_type_can_build` and friends read a build preview off the Tool registry, which is
## authored content, and CLAUDE.md §A unit test does not assert facts about authored content
## is explicit that a mechanic is tested against a fixture the test builds. What is under
## test is the arithmetic of demand and which types it permits.

const BUILDER: StringName = &"test_builder"
const CARRIER: StringName = &"test_carrier"
const CRUSHER: StringName = &"test_crusher"
const SOLDIER: StringName = &"test_soldier"
const TRANSPORT: StringName = &"test_transport"
const SPOTTER: StringName = &"test_spotter"


class FakeBot:
	extends Bot
	var builders: Dictionary = {}  ## type -> true
	var capturers: Dictionary = {}
	var combat_capable: Dictionary = {}
	var utility: Dictionary = {}
	var owned: Dictionary = {}  ## type -> count
	var clusters: int = 0
	var has_camp: bool = true
	var idle_producers: Array = []

	func can_afford(_a_type: StringName) -> bool:
		return true

	func enemy_demand_map() -> Dictionary:
		return {}

	func get_idle_production_structures() -> Array:
		return idle_producers

	func unit_can_attack(_a_type) -> bool:
		return false  # every producible type here is utility, so the utility rung runs

	func unit_is_utility(a_type) -> bool:
		return bool(utility.get(a_type, false))

	func unit_type_can_build(a_type) -> bool:
		return bool(builders.get(a_type, false))

	func unit_type_can_capture(a_type) -> bool:
		return bool(capturers.get(a_type, false))

	func unit_type_has_combat_utility(a_type) -> bool:
		return bool(combat_capable.get(a_type, false))

	## The synergy types (2026-10-10): which types carry, which spot, and whether a gun stands.
	var transports: Dictionary = {}
	var spotters: Dictionary = {}
	var gun_structures: Array = []

	func unit_type_is_transport(a_type) -> bool:
		return bool(transports.get(a_type, false))

	func unit_type_is_mobile_spotter(a_type) -> bool:
		return bool(spotters.get(a_type, false))

	func get_structures() -> Array:
		return gun_structures

	func get_units_of_type(a_type: StringName) -> Array:
		var out: Array = []
		for _i: int in int(owned.get(a_type, 0)):
			out.append(null)
		return out

	## Every owned unit, flattened out of `owned` — what the pool-wide scout term counts.
	## Instances are pooled and rebuilt only when `owned` changes: the count is asked once per
	## type per think, and minting a fresh Actor each time leaks physics RIDs.
	var _pool: Array = []
	var _pool_key: Dictionary = {}

	func get_units() -> Array:
		if _pool_key != owned:
			release_pool()
			for t: StringName in owned:
				for _i: int in int(owned[t]):
					var u := Actor.new()
					u.id = t
					_pool.append(u)
			_pool_key = owned.duplicate()
		return _pool

	func release_pool() -> void:
		for u: Actor in _pool:
			u.free()
		_pool = []
		_pool_key = {}

	func get_deposit_structures() -> Array:
		return [null] if has_camp else []

	func capturable_clusters(_a_link_distance: float = 8.0) -> Array:
		var out: Array = []
		for _i: int in clusters:
			out.append(null)
		return out


class StubActuator:
	extends BotActuator
	var trains: Array = []

	func train(_a_structure: Actor, a_type: StringName) -> bool:
		trains.append(a_type)
		return true


var _bot: FakeBot
var _act: StubActuator


func before_each() -> void:
	_bot = FakeBot.new()
	_bot.utility = {BUILDER: true, CARRIER: true, CRUSHER: true}
	_bot.builders = {BUILDER: true}
	_bot.capturers = {CARRIER: true, CRUSHER: true}
	_bot.combat_capable = {CRUSHER: true}
	_bot.owned = {BUILDER: 9, CARRIER: 9, CRUSHER: 9}  # pool is past the scout budget
	_bot.technology_mapping = {
		BUILDER: TechnologySpec.new(200, 0, 0, 30),
		CARRIER: TechnologySpec.new(300, 0, 0, 30),
		CRUSHER: TechnologySpec.new(400, 0, 0, 30),
		SOLDIER: TechnologySpec.new(150, 0, 0, 30),
	}
	_bot.energy = 5000  # the reserve is tests/test_BotEconomyReserve.gd's subject, not this one's
	_act = StubActuator.new(null)


func after_each() -> void:
	_bot.release_pool()
	_bot.free()


func _production() -> BotProduction:
	var production := BotProduction.new(_bot, _act)
	production.utility_unit_cap = 99  # the ceiling is tested on its own, below
	production.scout_unit_budget = 0
	production.build_concurrency = 1
	return production


func _producer_of(a_types: Array[StringName]) -> Actor:
	var structure := autofree(Actor.new()) as Actor
	structure.production = Production.new()
	structure.production.producible_types = a_types
	structure.add_child(structure.production)
	return structure


# ─── DEMAND IS THE SUM OF THE LIVE ERRANDS ──────────────────────────────────


func test_a_builder_is_wanted_per_concurrent_build_job_plus_a_spare() -> void:
	var production := _production()
	production.build_concurrency = 3
	assert_eq(production._utility_demand_for(BUILDER), 4)


func test_serialised_building_still_wants_one_builder() -> void:
	var production := _production()
	production.build_concurrency = 1
	assert_eq(production._utility_demand_for(BUILDER), 2, "one job, one builder, one spare")


func test_a_carrier_is_wanted_per_capturable_cluster() -> void:
	_bot.clusters = 3
	assert_eq(_production()._utility_demand_for(CARRIER), 4)


func test_a_carrier_with_no_prey_in_sight_is_wanted_only_as_the_spare() -> void:
	_bot.clusters = 0
	assert_eq(
		_production()._utility_demand_for(CARRIER),
		1,
		"a utility unit with no errand is the definition of too many"
	)


func test_capture_demand_is_zero_without_somewhere_to_bank_prisoners() -> void:
	# The same gate BotOpportunist._gather_captures applies before it will dispatch anyone:
	# no camp, no completable loop, no errand.
	_bot.clusters = 5
	_bot.has_camp = false
	assert_eq(_production()._utility_demand_for(CARRIER), 1)


func test_the_cluster_count_is_computed_once_per_think() -> void:
	# Clustering is O(n²) over visible prey and the utility rung runs per idle producer.
	var production := _production()
	_bot.clusters = 2
	_bot.idle_producers = [
		_producer_of([CARRIER] as Array[StringName]), _producer_of([CARRIER] as Array[StringName])
	]
	production.tick()
	assert_eq(production._capture_errands, 2, "cached, and cached at the real value")


# ─── THE TWO CORRECTIONS ────────────────────────────────────────────────────


func test_a_crusher_is_wanted_one_deeper_because_it_is_army_as_well_as_errand() -> void:
	# BotMilitary._combat_units claims anything with combat utility, so a Stock Truck between
	# capture errands is in the attack wave rather than standing idle.
	_bot.clusters = 0
	var production := _production()
	assert_eq(production._utility_demand_for(CRUSHER), production._utility_demand_for(CARRIER) + 1)


func test_the_scout_allowance_raises_demand_only_while_the_pool_is_short_of_it() -> void:
	# Scouting is a POOL errand — any spare body takes it — so it must not be counted once
	# per type. With the fog-limited ATTACK objective, a bot with nothing to look with has
	# no offensive at all, which is why the term exists.
	var production := _production()
	production.scout_unit_budget = 2
	_bot.owned = {BUILDER: 0, CARRIER: 0, CRUSHER: 0}
	var short: int = production._utility_demand_for(BUILDER)
	_bot.owned = {BUILDER: 1, CARRIER: 1, CRUSHER: 1}  # pool of 3, budget of 2
	assert_eq(short, production._utility_demand_for(BUILDER) + 1)


func test_a_blind_bot_never_gets_the_scouting_allowance() -> void:
	var production := _production()
	production.scout_unit_budget = 0
	_bot.owned = {BUILDER: 0, CARRIER: 0, CRUSHER: 0}
	assert_eq(production._utility_demand_for(BUILDER), 2, "PASSIVE plays blind, and buys none")


# ─── THE CAP IS A CEILING, NOT THE DECISION ─────────────────────────────────


func test_the_cap_bounds_a_demand_that_would_otherwise_run_away() -> void:
	_bot.clusters = 50  # a map strewn with capturable infantry
	var production := _production()
	production.utility_unit_cap = 3
	assert_eq(production._utility_demand_for(CARRIER), 3)


func test_a_cap_of_zero_removes_utility_units_entirely() -> void:
	var production := _production()
	production.utility_unit_cap = 0
	assert_eq(production._utility_demand_for(BUILDER), 0)


func test_the_cap_is_no_longer_a_floor() -> void:
	# THE BUG THE QUESTION WAS ABOUT. The cap says 3 are permitted; the work says one carrier
	# is wanted, and the bot used to build to the cap regardless.
	_bot.clusters = 0
	_bot.owned = {BUILDER: 0, CARRIER: 1, CRUSHER: 0}
	var production := _production()
	production.utility_unit_cap = 3
	_bot.idle_producers = [_producer_of([CARRIER] as Array[StringName])]
	production.tick()
	assert_eq(_act.trains, [], "one carrier and no prey is not a reason to build a second")


func test_the_bot_still_builds_the_utility_unit_it_has_work_for() -> void:
	_bot.clusters = 2
	_bot.owned = {BUILDER: 0, CARRIER: 1, CRUSHER: 0}
	var production := _production()
	_bot.idle_producers = [_producer_of([CARRIER] as Array[StringName])]
	production.tick()
	assert_eq(_act.trains, [CARRIER], "two clusters and a spare want three carriers")


func test_a_type_at_its_demand_is_passed_over_for_one_that_is_not() -> void:
	# The picker is still cheapest-first among the permitted types; what changed is which
	# types are permitted. The cheap carrier is satisfied, so the dearer builder is made.
	_bot.clusters = 0
	_bot.owned = {BUILDER: 0, CARRIER: 5, CRUSHER: 0}
	var production := _production()
	_bot.idle_producers = [_producer_of([CARRIER, BUILDER] as Array[StringName])]
	production.tick()
	assert_eq(_act.trains, [BUILDER])


# ─── THE SENSES THE DEMAND IS BUILT FROM ────────────────────────────────────
#
# `Bot.unit_type_*` classify a type by the components on its build preview, the same way
# `unit_is_utility` and `unit_can_attack` already do. Tested against a preview the test
# assembles rather than against a shipped unit: what is under test is the RULE (which
# component means which errand), and a piece's component set is authored content.


## A Bot whose build previews the test builds by hand.
class PreviewBot:
	extends Bot
	var previews: Dictionary = {}  ## type -> Node

	func _preview_for_type(a_type) -> Node:
		return previews.get(a_type)


func _preview(a_children: Dictionary) -> Node:
	var root := autofree(Node3D.new()) as Node3D
	for name: String in a_children:
		var node: Node = a_children[name]
		node.name = name
		root.add_child(node)
	return root


func test_a_type_that_builds_is_recognised_from_its_builds_component() -> void:
	var bot := autofree(PreviewBot.new()) as PreviewBot
	bot.previews = {
		BUILDER: _preview({"Builds": Builds.new()}),
		SOLDIER: _preview({}),
	}
	assert_true(bot.unit_type_can_build(BUILDER))
	assert_false(bot.unit_type_can_build(SOLDIER))


func test_a_capturer_needs_a_garrison_with_room_in_it() -> void:
	# Garrison.can_capture asks the captor for a cage that CAPTURES, with space; a hold of
	# capacity 0 is a component without a job, and a hold that does not capture (a transport's)
	# is not a carrier either, however roomy.
	var full_cage := Garrison.new()
	full_cage.capacity = 3
	full_cage.captures = true
	var no_cage := Garrison.new()
	no_cage.capacity = 0
	no_cage.captures = true
	var transport_hold := Garrison.new()
	transport_hold.capacity = 6
	var bot := autofree(PreviewBot.new()) as PreviewBot
	bot.previews = {
		CARRIER: _preview({"Garrison": full_cage}),
		BUILDER: _preview({"Garrison": no_cage}),
		SOLDIER: _preview({"Garrison": transport_hold}),
	}
	assert_true(bot.unit_type_can_capture(CARRIER))
	assert_false(bot.unit_type_can_capture(BUILDER))
	assert_false(bot.unit_type_can_capture(SOLDIER))


func test_combat_utility_is_armed_or_able_to_crush() -> void:
	# The type-level form of Bot.unit_has_combat_utility, and the reason the Stock Truck is
	# not priced as pure overhead: an empty Loadout, and it runs light infantry over.
	var heavy := Movement.new()
	heavy.crush_class = Movement.CrushClass.LARGE
	var light := Movement.new()
	light.crush_class = Movement.CrushClass.TINY
	var bot := autofree(PreviewBot.new()) as PreviewBot
	bot.previews = {
		CRUSHER: _preview({"Locomotion": heavy, "Loadout": Loadout.new()}),
		BUILDER: _preview({"Locomotion": light, "Loadout": Loadout.new()}),
	}
	assert_true(bot.unit_type_can_crush(CRUSHER))
	assert_false(bot.unit_type_can_crush(BUILDER))
	assert_true(bot.unit_type_has_combat_utility(CRUSHER), "unarmed, and not harmless")
	assert_false(bot.unit_type_has_combat_utility(BUILDER))


## A Bot whose capturable prey the test places directly, so the grouping is what is measured.
class PreyBot:
	extends Bot
	var prey: Array = []
	var neutrals: Array = []

	func get_capturable_enemies() -> Array:
		return prey

	func get_neutral_terrestrials() -> Array:
		return neutrals


## A Actor that can live in the tree without a scene behind it — the same shape
## tests/test_BotCombatUtility.gd uses, and for the same reason. Clustering reads
## `global_position`, which only answers inside the tree.
class StubPiece:
	extends Actor

	static func make() -> StubPiece:
		var piece := StubPiece.new()
		for pair: Array in [
			["Ownership", Ownership.new()],
			["AvoidanceObstacle", NavigationObstacle3D.new()],
			["Veterancy", Veterancy.new()]
		]:
			var node: Node = pair[1]
			node.name = pair[0]
			piece.add_child(node)
		var bar := Node3D.new()
		bar.name = "HPBar"
		var fill := Sprite3D.new()
		fill.name = "HPBarFill"
		bar.add_child(fill)
		piece.add_child(bar)
		return piece

	func _ready() -> void:
		set_process(false)
		set_physics_process(false)


func _prey_at(a_host: Node, a_positions: Array) -> Array:
	var out: Array = []
	for p: Vector3 in a_positions:
		var piece: StubPiece = StubPiece.make()
		a_host.add_child(piece)
		piece.global_position = p
		out.append(piece)
	return out


func test_capturable_prey_is_grouped_into_one_errand_per_knot() -> void:
	# One truck collects a knot of infantry in a single trip, so the errand count is CLUSTERS
	# and not bodies — otherwise the fleet would be sized against the map's population.
	var bot := add_child_autofree(PreyBot.new()) as PreyBot
	bot.prey = _prey_at(bot, [Vector3.ZERO, Vector3(1, 0, 0), Vector3(2, 0, 0)])
	bot.neutrals = _prey_at(bot, [Vector3(60, 0, 0), Vector3(61, 0, 0)])
	assert_eq(bot.capturable_clusters().size(), 2, "two knots, two trips")


func test_no_prey_anywhere_is_no_capture_errand() -> void:
	var bot := add_child_autofree(PreyBot.new()) as PreyBot
	assert_eq(bot.capturable_clusters().size(), 0)


# ─── SYNERGY PIECES ARE WANTED WHILE THEIR WORK EXISTS (Alex, 2026-10-10) ────────────


func test_a_transport_is_wanted_while_a_lift_is_wanted_and_the_bot_owns_none() -> void:
	_bot.utility[TRANSPORT] = true
	_bot.transports = {TRANSPORT: true}
	_bot.technology_mapping[TRANSPORT] = TechnologySpec.new(500, 0, 0, 30)
	var production := _production()
	_bot.lift_wanted = false
	assert_eq(production._utility_demand_for(TRANSPORT), 1, "the spare alone")
	_bot.lift_wanted = true
	assert_eq(production._utility_demand_for(TRANSPORT), 2, "one lift, one transport")


func test_a_mobile_spotter_is_wanted_while_a_gun_stands_unspotted() -> void:
	_bot.utility[SPOTTER] = true
	_bot.spotters = {SPOTTER: true}
	_bot.technology_mapping[SPOTTER] = TechnologySpec.new(700, 0, 0, 30)
	FakePieces.install_ability(&"fake_gun", {"command": "command_bombard"})
	var gun: Actor = FakePieces.structure({"abilities": [{"grants": [&"fake_gun"]}]})
	add_child_autofree(gun)
	var production := _production()
	assert_eq(production._utility_demand_for(SPOTTER), 1, "no gun: the spare alone")
	_bot.gun_structures = [gun]
	assert_eq(production._utility_demand_for(SPOTTER), 2, "a gun with nothing to spot for it")
	FakePieces.restore_abilities()
