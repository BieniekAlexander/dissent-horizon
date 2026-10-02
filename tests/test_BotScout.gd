extends GutTest

## Unit tests for BotScout's scout-suitability score — "what makes a good scout",
## asked as a comparison over facts rather than as a rule.
##
## Synthetic Commandables stand in for owned units. They are never added to the
## SceneTree, so their @onready component fields stay null and can be assigned
## directly — which is the point: the score reads speed, vision, price and
## component presence, and nothing else needs to exist for it to be exercised.
##
## A bare Bot is enough to construct BotScout: its map is null, so _build_scout_grid
## no-ops and the scoring helpers can be called directly.

var _bot: Bot
var _scout: BotScout


func before_each() -> void:
	_bot = Bot.new()
	_scout = BotScout.new(_bot, null)


func after_each() -> void:
	_bot.free()


## A stand-in unit. Out of tree deliberately (see the file comment) and freed with the
## test, so the component fields below are ours to set.
func _unit(a_speed: float, a_vision: float) -> Commandable:
	return _build_unit(a_speed, a_vision, autofree(Commandable.new()) as Commandable)


## A stand-in unit OWNED by the bot — parented to it, so Bot._owned_units() sees it and
## the bot's free() takes it with them. Not autofree'd: it already has an owner.
func _owned_unit(a_speed: float, a_vision: float) -> Commandable:
	var u := Commandable.new()
	_bot.add_child(u)
	return _build_unit(a_speed, a_vision, u)


func _build_unit(a_speed: float, a_vision: float, a_unit: Commandable) -> Commandable:
	var u: Commandable = a_unit
	# @onready, so null on an out-of-tree instance — and every "is this unit free" question
	# the module asks goes through it.
	u.command_receiver = CommandReceiver.new()
	u.movement = Movement.new()
	u.movement.speed = a_speed
	u.add_child(u.movement)
	# The vision shape is parented to the TEST, not to the unit: Commander.vision_radius
	# reads its global_transform for scale, and an out-of-tree node has none. It only has to
	# be reachable from the field, never a child of the unit.
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = a_vision
	shape.shape = sphere
	add_child_autofree(shape)
	u.vision_range_shape = shape
	return u


## Arm a unit: a Loadout holding one Weapon, which is what the army lays claim to.
func _arm(a_unit: Commandable) -> Commandable:
	var loadout := Loadout.new()
	loadout.add_child(Weapon.new())
	a_unit.weapon_inventory = loadout
	a_unit.add_child(loadout)
	return a_unit


## Give a unit the Builds component, by node name — which is how the bot classifies it.
func _make_builder(a_unit: Commandable) -> Commandable:
	var builds := Node.new()
	builds.name = "Builds"
	a_unit.add_child(builds)
	return a_unit


## Score every candidate against one shared set of scales, as _pick_best_scout does.
func _scores(a_units: Array) -> Array:
	var scales: Dictionary = _scout._score_scales(a_units)
	return a_units.map(func(u: Commandable): return _scout._scout_score(u, scales))


func test_faster_wins_when_nothing_else_differs() -> void:
	var slow := _unit(2.0, 5.0)
	var fast := _unit(6.0, 5.0)
	var scores: Array = _scores([slow, fast])
	assert_gt(scores[1], scores[0], "speed is what a scout converts into map coverage")


func test_better_vision_wins_when_nothing_else_differs() -> void:
	var blind := _unit(4.0, 2.0)
	var sighted := _unit(4.0, 9.0)
	var scores: Array = _scores([blind, sighted])
	assert_gt(scores[1], scores[0], "vision is the other half of coverage")


func test_an_expensive_unit_is_a_worse_scout_than_an_identical_cheap_one() -> void:
	var cheap := _unit(4.0, 5.0)
	var dear := _unit(4.0, 5.0)
	cheap.id = &"cheap_scout"
	dear.id = &"dear_scout"
	_bot.technology_mapping[&"cheap_scout"] = TechnologySpec.new(50, 0, 0, 30)
	_bot.technology_mapping[&"dear_scout"] = TechnologySpec.new(900, 0, 0, 30)
	var scores: Array = _scores([cheap, dear])
	assert_gt(scores[0], scores[1], "a scout is risked alone, so replacement price counts")


func test_a_slow_truck_beats_a_fast_soldier_because_the_soldier_is_needed() -> void:
	# The Colonial opening, derived rather than named: the Stock Truck is slower than an
	# Irregular but unarmed, and its capture errand has no target yet — so nothing else
	# wants it. This is the whole point of the responsibility term.
	var truck := _unit(3.0, 6.0)
	var soldier := _arm(_unit(5.0, 6.0))
	var scores: Array = _scores([truck, soldier])
	assert_gt(scores[0], scores[1], "a live responsibility outweighs a speed advantage")


func test_an_armed_unit_carries_one_responsibility() -> void:
	assert_eq(_scout._applicable_responsibility_count(_arm(_unit(4.0, 5.0))), 1)


func test_an_idle_utility_unit_carries_none() -> void:
	assert_eq(_scout._applicable_responsibility_count(_unit(4.0, 5.0)), 0)


func test_the_last_builder_is_needed_but_a_second_one_is_spare() -> void:
	var only_builder := _make_builder(_owned_unit(4.0, 5.0))
	assert_eq(
		_scout._applicable_responsibility_count(only_builder),
		1,
		"pulling the last builder away stalls construction"
	)

	_make_builder(_owned_unit(4.0, 5.0))
	assert_eq(
		_scout._applicable_responsibility_count(only_builder),
		0,
		"with a second builder owned, neither is the last one"
	)


func test_a_unit_carrying_occupants_has_a_delivery_to_make() -> void:
	var loaded := _unit(4.0, 5.0)
	var garrison := Garrison.new()
	loaded.garrison = garrison
	loaded.add_child(garrison)
	var occupant := Commandable.new()
	garrison.add_child(occupant)
	garrison._garrisoned.append(occupant)
	assert_eq(
		_scout._applicable_responsibility_count(loaded),
		1,
		"a full transport is on an errand already"
	)


func test_scales_never_divide_by_zero() -> void:
	var scales: Dictionary = _scout._score_scales([_unit(0.0, 0.0)])
	assert_eq(scales["speed"], 1.0)
	assert_eq(scales["vision"], 1.0)


# ─── IS ANOTHER SCOUT WORTH IT ───────────────────────────────────────────────
#
# The trade-off, priced in energy: what the map is worth against what having the unit away
# costs. The scout grid is empty here (a bare Bot has no map), so stale_fraction is driven
# by writing grid points directly — the arithmetic is the subject, not the LOS sweep.


## Make the grid `a_stale_fraction` blind, out of ten points.
func _set_staleness(a_stale_fraction: float) -> void:
	var stale_count: int = int(round(a_stale_fraction * 10.0))
	for i: int in range(10):
		# seconds_elapsed() is 0 on a bare Bot, so anything below -SCOUT_EXPIRATION_TIMER
		# has expired and anything above it is fresh.
		_scout._scout_grid[Vector2i(i, 0)] = (
			-(BotScout.SCOUT_EXPIRATION_TIMER + 1.0) if i < stale_count else 0.0
		)


## A candidate scout costing `a_cost` energy.
func _candidate(a_cost: int) -> Commandable:
	var u := _unit(4.0, 5.0)
	u.id = &"candidate"
	_bot.technology_mapping[u.id] = TechnologySpec.new(a_cost, 0, 0, 30)
	return u


func test_a_blind_bot_scouts_even_with_something_valuable() -> void:
	_set_staleness(1.0)
	assert_true(
		_scout._scouting_is_worth_it(_candidate(300)),
		"knowing nothing is worth risking a lot to fix"
	)


func test_a_bot_that_can_see_everything_does_not_bother() -> void:
	_set_staleness(0.0)
	assert_false(
		_scout._scouting_is_worth_it(_candidate(10)),
		"nothing left to learn, so no absence is worth it"
	)


func test_a_cheap_unit_is_sent_where_an_expensive_one_is_not() -> void:
	_set_staleness(0.4)
	assert_true(_scout._scouting_is_worth_it(_candidate(50)))
	assert_false(
		_scout._scouting_is_worth_it(_candidate(600)),
		"same information, and now it costs more than it is worth"
	)


func test_each_extra_scout_is_worth_less_than_the_last() -> void:
	# The whole answer to "why not scout with everything": value halves with the second
	# scout and thirds with the third, while each costs full price.
	_set_staleness(0.5)
	var candidate := _candidate(300)
	assert_true(_scout._scouting_is_worth_it(candidate), "the first scout pays")
	_scout._scouts = [_unit(4.0, 5.0)]
	assert_false(
		_scout._scouting_is_worth_it(candidate),
		"a second scout buys half as much for the same price"
	)


func test_staleness_is_the_fraction_of_the_map_gone_dark() -> void:
	_set_staleness(0.3)
	assert_almost_eq(_scout.stale_fraction(), 0.3, 0.001)


func test_an_empty_grid_is_not_blind() -> void:
	# A bot whose map never built a grid must not read as maximally blind and scout forever.
	assert_eq(_scout.stale_fraction(), 0.0)


func test_no_allowance_releases_every_scout() -> void:
	_scout.unit_budget = 0
	_scout._scouts = [_unit(4.0, 5.0)]
	_scout._update_scouts()
	assert_eq(_scout._scouts.size(), 0, "released, so the military can pick them up")


# ─── HOLDING A CLAIM ─────────────────────────────────────────────────────────
#
# A scout used to be dropped the moment anything else re-tasked it, which made this the
# weakest claimant in the bot: it runs FIRST so it gets first refusal, then surrendered
# whatever it picked to BotMilitary's whole-army sweep — and that sweep takes the Colonial
# Stock Truck, because a truck can crush. The module now gives a scout up for a real errand
# or once the absence stops paying, and re-issues the waypoint for anything else.


## An order of `a_class` on `a_unit`, built the way a manager would build it.
func _order(a_unit: Commandable, a_class: GDScript) -> Commandable:
	a_unit._command = a_class.new(CommandMessage.new(null, null, null, Vector3.ZERO))
	return a_unit


## A scout already out, with the grid `a_stale_fraction` blind so the retention test has a
## number to price against.
func _scouting(a_cost: int, a_stale_fraction: float) -> Commandable:
	_set_staleness(a_stale_fraction)
	var u := _candidate(a_cost)
	_scout._scouts = [u]
	return u


func test_an_attack_move_does_not_take_a_scout_away() -> void:
	# The reported bug, at module level: BotMilitary re-tasks every unit with combat utility
	# on each posture or objective change, the truck is one of them, and yielding to that
	# cost the bot its best scout on the first think of every match.
	var truck := _scouting(400, 1.0)
	_order(truck, AttackMove)
	assert_true(_scout._still_scouting(truck, 1), "a standing rally is not a claim on this unit")


func test_a_real_errand_takes_a_scout_away() -> void:
	var truck := _scouting(400, 1.0)
	_order(truck, Build)
	assert_false(
		_scout._still_scouting(truck, 1),
		"a job somebody decided this unit should do runs to completion"
	)


func test_a_scout_is_released_once_the_map_is_known() -> void:
	# What stops claim-holding from being a unit the army can never have back.
	var truck := _scouting(400, 1.0)
	_order(truck, AttackMove)
	assert_true(_scout._still_scouting(truck, 1), "precondition: still worth it while blind")

	_set_staleness(0.0)
	assert_false(
		_scout._still_scouting(truck, 1), "nothing left to learn, so the absence stops paying"
	)


func test_a_garrisoned_scout_is_no_longer_scouting() -> void:
	# A unit run over by a truck, or ordered into a bunker, is a valid object that has left
	# the scene tree — so it has no position for the stall test to measure.
	var truck := _scouting(400, 1.0)
	truck.garrisoned_in = autofree(Garrison.new()) as Garrison
	assert_false(_scout._still_scouting(truck, 1))


func test_a_scout_that_died_is_no_longer_scouting() -> void:
	# The sweep runs through a Variant precisely so this case cannot abort the think pass.
	var dead := Commandable.new()
	dead.free()
	assert_false(_scout._still_scouting(dead, 1))


func test_an_attack_move_still_counts_as_a_re_task() -> void:
	# Held, but the waypoint is gone, so the next think has to re-issue it. The two questions
	# are separate and both are asked.
	var truck := _order(_candidate(400), AttackMove)
	assert_true(_scout._was_retasked(truck), "its order is no longer the move we gave it")
	assert_false(_scout._yields_to_errand(truck), "…but nobody decided this unit should do it")


func test_a_held_scout_is_priced_as_the_scout_it_already_is() -> void:
	# Rank matters: asking the claim-time question of a scout already out would price the
	# first one as if it were a second, halve its value and release it for nothing.
	_set_staleness(0.5)
	var candidate := _candidate(300)
	_scout._scouts = [candidate]
	assert_true(_scout._scouting_is_worth_it(candidate, 1), "it is the FIRST scout out")
	assert_false(
		_scout._scouting_is_worth_it(candidate), "and would not be worth adding as a second one"
	)


# ─── WHICH UNIT IS PICKED ────────────────────────────────────────────────────


func test_the_best_scout_the_bot_can_afford_is_picked_not_simply_the_best() -> void:
	# The scorer rewards capability and the price test punishes replacement cost, so the
	# top-scoring candidate is the one most likely to be unaffordable. Returning it and
	# letting the caller reject it meant a think that claimed nothing, every think.
	_set_staleness(0.5)
	var dear := _owned_unit(6.0, 9.0)
	dear.id = &"dear_scout"
	_bot.technology_mapping[dear.id] = TechnologySpec.new(900, 0, 0, 30)
	var cheap := _owned_unit(3.0, 5.0)
	cheap.id = &"cheap_scout"
	_bot.technology_mapping[cheap.id] = TechnologySpec.new(50, 0, 0, 30)

	var scales: Dictionary = _scout._score_scales([dear, cheap])
	assert_gt(
		_scout._scout_score(dear, scales),
		_scout._scout_score(cheap, scales),
		"precondition: the expensive one is the better scout on paper"
	)
	assert_false(
		_scout._scouting_is_worth_it(dear), "precondition: and the bot cannot justify losing it"
	)
	assert_eq(_scout._pick_scout(), cheap, "so it sends the one it can justify")


func test_nobody_is_picked_when_nobody_is_worth_sending() -> void:
	_set_staleness(0.05)
	var dear := _owned_unit(6.0, 9.0)
	dear.id = &"dear_scout"
	_bot.technology_mapping[dear.id] = TechnologySpec.new(900, 0, 0, 30)
	assert_eq(_scout._pick_scout(), null)


# ─── WHERE THE SCOUT GOES ────────────────────────────────────────────────────
#
# The selector is exercised against a SYNTHETIC grid: a bare Bot builds none, so the points
# and their world positions are written directly and the map transform stays IDENTITY. Home
# is the origin (a bot with no structures and no units centroids there), so "far from home"
# is simply "far along +X".

const EXPIRED: float = -(BotScout.SCOUT_EXPIRATION_TIMER + 1.0)


## Put a grid point at (`a_x`, 0) that was last seen at `a_last_seen`; `a_ever_seen` records
## whether it was ever in real line of sight.
func _point(a_i: int, a_x: float, a_last_seen: float, a_ever_seen: bool = false) -> Vector2i:
	var idx := Vector2i(a_i, 0)
	_scout._scout_grid[idx] = a_last_seen
	_scout._scout_grid_positions[idx] = Vector3(a_x, 0.0, 0.0)
	if a_ever_seen:
		_scout._ever_seen[idx] = true
	return idx


## Ask the selector where a scout standing at (`a_x`, 0) would go, on a map `a_span` wide.
## Drives _best_errand rather than _next_scout_point because the facts it needs — a position,
## a speed, a vision window — are exactly what a live Commandable would have to be in the
## scene tree to supply, and the choice is what is under test, not the unit.
func _errand_from(a_x: float, a_span: float = 100.0) -> Variant:
	_scout._map_width = a_span
	_scout._map_depth = 0.0
	var window: Array = _scout._vision_window(10.0)
	var frontier: Variant = _scout._best_errand(Vector2(a_x, 0.0), 3.0, window, true)
	return (
		frontier if frontier != null else _scout._best_errand(Vector2(a_x, 0.0), 3.0, window, false)
	)


## The world X of the point the selector chose, or NAN when it chose nothing.
func _errand_x(a_x: float) -> float:
	var idx: Variant = _errand_from(a_x)
	return NAN if idx == null else _scout._scout_grid_positions[idx].x


func test_a_scout_crosses_to_open_map_rather_than_shaving_its_own_frontier() -> void:
	# Nearest-first is the correct answer to "cover the most ground per second" and the wrong
	# answer to "find somebody": it spirals, and a spiral fills in the bot's own corner before
	# it ever starts on the far side. Measured on a Colonial mirror, the closest the seen set
	# got to the opposing start point did not move at all over the first two minutes.
	_point(1, 5.0, EXPIRED)  # the nearest unseen cell, on its own
	for i: int in range(12, 21):  # a dark region at the far end
		_point(i, float(i) * 5.0, EXPIRED)
	assert_gt(_errand_x(0.0), 40.0, "the open half of the map is where an unfound enemy is")


func test_the_nearest_point_is_taken_when_it_is_the_only_frontier_left() -> void:
	# The prior is a tie-breaker over real information, not a compulsion to walk away from
	# everything: with nothing dark in the distance, the near cell is the errand.
	_point(1, 5.0, EXPIRED)
	for i: int in range(12, 21):
		_point(i, float(i) * 5.0, 0.0, true)  # far end: seen, and fresh
	assert_eq(_errand_x(0.0), 5.0)


func test_a_never_seen_point_beats_a_stale_one_that_is_nearer_and_larger() -> void:
	# The frontier-first ordering, re-asserted under the new selector: a cell nobody has ever
	# laid eyes on is not the same as one seen 61 seconds ago, and the second kind is always
	# nearer because the bot's own base refreshes a disc around home forever.
	for i: int in range(1, 6):
		_point(i, float(i) * 5.0, EXPIRED, true)  # a big stale block, right next door
	_point(19, 95.0, EXPIRED)  # one never-seen cell, far away
	assert_eq(_errand_x(0.0), 95.0)


func test_a_fresh_point_is_never_an_errand() -> void:
	_point(1, 5.0, 0.0)
	assert_eq(_errand_from(0.0), null, "nothing has expired, so there is nothing to go and look at")


func test_the_enemy_is_likelier_the_further_a_point_is_from_home() -> void:
	_scout._map_width = 100.0
	_scout._map_depth = 0.0
	var home := Vector2.ZERO
	assert_gt(
		_scout._enemy_prior(Vector2(90.0, 0.0), home),
		_scout._enemy_prior(Vector2(10.0, 0.0), home),
		"the opponent is not standing next to my own base, because I can see my own base"
	)


func test_the_bot_does_not_write_its_own_approaches_off_entirely() -> void:
	_scout._map_width = 100.0
	_scout._map_depth = 0.0
	assert_almost_eq(
		_scout._enemy_prior(Vector2.ZERO, Vector2.ZERO),
		BotScout.HOME_PRIOR_FLOOR,
		0.001,
		"a raid still has to be noticed"
	)


## The errand search may be split across ticks (BotScout._drain_dispatch). Scored one grid
## point at a time, it must choose exactly what an uninterrupted search chooses: the facts it
## scores against are fixed when the search starts, so slicing can never reorder the result.
func test_an_errand_search_split_into_slices_chooses_the_same_point() -> void:
	for i: int in 30:
		_point(i, float(i) * 3.0, EXPIRED, i % 4 == 0)
	_scout._map_width = 100.0
	var window: Array = _scout._vision_window(10.0)
	var whole: Variant = _scout._best_errand(Vector2(10.0, 0.0), 3.0, window, true)
	var search: Dictionary = _scout._errand_search(null, Vector2(10.0, 0.0), 3.0, window, true)
	var slices: int = 1
	while not _scout._continue_errand_search(search, 1):
		slices += 1
	assert_gt(slices, 2, "the search really was split")
	assert_not_null(whole)
	assert_eq(search["best_idx"], whole)
