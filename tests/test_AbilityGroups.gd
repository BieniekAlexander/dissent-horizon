extends GutTest

## Ability charges, and the pools that abilities SHARE.
##
## Two rules carry the whole model:
##   • every ability is charge-based — an ability that is "just a cooldown" is a pool of
##     ONE charge, not a second mechanic, which is why ABILITY_NO_CHARGES can speak for
##     every ability in the game;
##   • abilities in one pool share it — use any of an Operations Center's four and all
##     four go down together.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_AbilityGroups.gd -gexit

const A: StringName = &"scan"
const B: StringName = &"freeze"
const C: StringName = &"mortar"


## An Abilities component with the given pools, ready to query. Kept out of the tree —
## _rebuild is what derives the live state, and _physics_process is driven by hand.
func _abilities(a_groups: Array) -> Abilities:
	var node := Abilities.new()
	var typed: Array[Dictionary] = []
	typed.assign(a_groups)
	node.groups = typed
	autofree(node)
	node._rebuild()
	return node


func _pool(a_grants: Array, a_charges: int = 1, a_cooldown_ticks: int = 30) -> Dictionary:
	return {"max_charges": a_charges, "cooldown_ticks": a_cooldown_ticks, "grants": a_grants}


func _tick(a_node: Abilities, a_times: int) -> void:
	for _i: int in a_times:
		a_node._physics_process(1.0 / 30.0)


# --- Granting --------------------------------------------------------------------

func test_it_grants_what_its_pools_list() -> void:
	var abilities := _abilities([_pool([A, B])])
	assert_true(abilities.grants(A))
	assert_true(abilities.grants(B))
	assert_false(abilities.grants(C), "and nothing else")


func test_an_ungranted_ability_is_never_ready() -> void:
	var abilities := _abilities([_pool([A])])
	assert_false(abilities.is_ready(C))
	assert_eq(abilities.charges_of(C), 0, "and reports no charges rather than lying")


func test_granted_abilities_lists_every_pool() -> void:
	var abilities := _abilities([_pool([A]), _pool([B, C])])
	var granted: Array = abilities.granted_abilities()
	granted.sort()
	var want: Array = [A, B, C]
	want.sort()
	assert_eq(granted, want)


# --- Sharing: the point of the feature ---------------------------------------------

func test_abilities_in_one_pool_share_its_charges() -> void:
	# The Operations Center case: use Scan and Freeze goes down with it.
	var abilities := _abilities([_pool([A, B])])
	assert_true(abilities.is_ready(A) and abilities.is_ready(B))
	assert_true(abilities.spend(A))
	assert_false(abilities.is_ready(A), "the one that fired is down")
	assert_false(abilities.is_ready(B), "and so is everything sharing its pool")


func test_separate_pools_do_not_affect_each_other() -> void:
	var abilities := _abilities([_pool([A]), _pool([B])])
	assert_true(abilities.spend(A))
	assert_false(abilities.is_ready(A))
	assert_true(abilities.is_ready(B), "a different pool is untouched")


func test_a_shared_pool_recharges_for_everything_at_once() -> void:
	var abilities := _abilities([_pool([A, B], 1, 10)])
	abilities.spend(A)
	_tick(abilities, 10)
	assert_true(abilities.is_ready(A))
	assert_true(abilities.is_ready(B), "one recharge brings the whole pool back")


# --- Charges ----------------------------------------------------------------------

func test_a_cooldown_only_ability_is_a_one_charge_pool() -> void:
	# There is deliberately no way to express an ability without charges.
	var abilities := _abilities([_pool([A], 1, 10)])
	assert_eq(abilities.max_charges_of(A), 1)
	assert_true(abilities.spend(A))
	assert_false(abilities.spend(A), "no second use until it comes back")


func test_a_multi_charge_pool_can_be_spent_more_than_once() -> void:
	var abilities := _abilities([_pool([A], 3, 10)])
	assert_true(abilities.spend(A))
	assert_true(abilities.spend(A))
	assert_eq(abilities.charges_of(A), 1)
	assert_true(abilities.is_ready(A), "still usable while below capacity")


func test_spending_nothing_leaves_nothing_spent() -> void:
	# A caller must not be able to half-fire an ability.
	var abilities := _abilities([_pool([A], 1, 10)])
	abilities.spend(A)
	assert_false(abilities.spend(A))
	assert_eq(abilities.charges_of(A), 0)


func test_charges_come_back_one_at_a_time() -> void:
	var abilities := _abilities([_pool([A], 2, 10)])
	abilities.spend(A)
	abilities.spend(A)
	_tick(abilities, 10)
	assert_eq(abilities.charges_of(A), 1, "one per cooldown, not all at once")
	_tick(abilities, 10)
	assert_eq(abilities.charges_of(A), 2)


func test_a_full_pool_does_not_count_down() -> void:
	var abilities := _abilities([_pool([A], 1, 10)])
	_tick(abilities, 50)
	assert_eq(abilities.charges_of(A), 1, "capacity is a ceiling, not a target")


# --- Capacity vs. starting stock ----------------------------------------------------

func test_a_pool_that_says_nothing_holds_one_charge_and_starts_full() -> void:
	var abilities := _abilities([{"cooldown_ticks": 10, "grants": [A]}])
	assert_eq(abilities.max_charges_of(A), 1, "max_charges defaults to 1")
	assert_eq(abilities.charges_of(A), 1, "and initial_charges defaults to max_charges")


func test_initial_charges_defaults_to_a_full_pool() -> void:
	var abilities := _abilities([{"max_charges": 3, "cooldown_ticks": 10, "grants": [A]}])
	assert_eq(abilities.charges_of(A), 3)


func test_a_pool_can_start_below_capacity() -> void:
	var abilities := _abilities([
		{"initial_charges": 1, "max_charges": 3, "cooldown_ticks": 10, "grants": [A]},
	])
	assert_eq(abilities.charges_of(A), 1)
	assert_eq(abilities.max_charges_of(A), 3, "capacity is unaffected by the starting stock")


func test_a_pool_can_start_empty_and_fills_after_one_cooldown() -> void:
	# The battery that must spin up before its first shot. Zero is meaningful for starting
	# stock even though it is meaningless for capacity.
	var abilities := _abilities([
		{"initial_charges": 0, "max_charges": 2, "cooldown_ticks": 10, "grants": [A]},
	])
	assert_false(abilities.is_ready(A), "nothing to spend at t=0")
	_tick(abilities, 10)
	assert_eq(abilities.charges_of(A), 1, "the cooldown ran from the start, not from a spend")


func test_a_starting_stock_above_capacity_is_clamped_to_it() -> void:
	var abilities := _abilities([
		{"initial_charges": 9, "max_charges": 2, "cooldown_ticks": 10, "grants": [A]},
	])
	assert_eq(abilities.charges_of(A), 2)


func test_spending_a_second_charge_does_not_delay_the_first() -> void:
	# The timer runs from the moment the pool dropped below capacity. Restarting it on each
	# spend would make a burst of uses push the refill further and further away.
	var abilities := _abilities([_pool([A], 2, 10)])
	abilities.spend(A)
	_tick(abilities, 9)
	abilities.spend(A)
	_tick(abilities, 1)
	assert_eq(abilities.charges_of(A), 1, "the running timer was not reset")


# --- The authored pieces ------------------------------------------------------------

func test_the_colonial_command_centre_shares_one_pool_across_four_abilities() -> void:
	# The case the feature was asked for. The pool used to sit on the Operations Center
	# (cl_tech1); the roster moved scan/freeze/promotion/beacon onto the command centre, and
	# this test follows the pool rather than the building.
	# load(), not a file-scope preload: this file sorts first, so a preload here runs
	# Tool's static initialiser before anything else in the suite has set the registry up,
	# which leaves Tool.for_name null for every later test (see CLAUDE.md on Tool's static
	# init). Loading inside the test defers it to a point where the registry is ready.
	var piece: Node = (load("res://scenes/entities/structures/cl/cl_commandCenter.tscn") as PackedScene).instantiate()
	autofree(piece)
	var abilities := piece.get_node_or_null("Abilities") as Abilities
	assert_not_null(abilities, "cl_commandCenter declares ability_groups")
	if abilities == null:
		return
	abilities._rebuild()
	for id: StringName in [&"scan", &"promotion", &"freeze", &"beacon"]:
		assert_true(abilities.grants(id), "it casts %s" % id)
	assert_eq(abilities.groups.size(), 1, "all four draw on ONE pool")
	abilities.spend(&"scan")
	assert_false(abilities.is_ready(&"freeze"), "so scanning spends freeze's charge too")
