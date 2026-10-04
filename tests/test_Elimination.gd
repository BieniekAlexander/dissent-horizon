extends GutTest

## Tests for the implicit "you have been wiped out" loss: Commander.has_anything_in_play()
## and the armed poll in Scenario that turns it into a game_over(false).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_Elimination.gd -gexit
##
## Everything here stays OUT of the scene tree. Scenario._ready builds commanders, fog, HUD
## and a camera rig, and Commandable._ready resolves a dozen component children that a bare
## .new() hasn't got — none of which this rule touches. Orphaned nodes run neither, so the
## check can be exercised on exactly the state it actually reads.

var _scenario: Scenario
var _player: Commander
var _saved_player_id: int


func before_each() -> void:
	_saved_player_id = RTSController.PLAYER_COMMANDER_ID
	RTSController.PLAYER_COMMANDER_ID = 1

	_player = Commander.new()
	_player.id = 1
	var neutral := Commander.new()
	neutral.id = 0

	_scenario = Scenario.new()
	_scenario.commanders = [neutral, _player]


func after_each() -> void:
	# PLAYER_COMMANDER_ID is a static on RTSController, so a test that left it moved would
	# leak into every later test in the run.
	RTSController.PLAYER_COMMANDER_ID = _saved_player_id
	for commander: Commander in _scenario.commanders:
		commander.free()
	_scenario.free()


## An owned entity, parented to the commander the way Entity.initialize() does it.
func _own(a_planned: bool = false) -> Commandable:
	var entity := Commandable.new()
	entity.is_planned = a_planned
	_player.add_child(entity)
	return entity


## An owned STRUCTURE: the same thing carrying the component that is the discriminator
## everywhere else in the codebase (has_node("Structure")), not a type or a group.
func _own_structure(a_planned: bool = false) -> Commandable:
	var entity: Commandable = _own(a_planned)
	var structure := Structure.new()
	structure.name = "Structure"
	entity.add_child(structure)
	return entity


## One physics tick of the elimination poll.
func _tick() -> void:
	_scenario._physics_process(0.0)


# --- Commander.has_anything_in_play -------------------------------------------


func test_a_commander_with_nothing_has_nothing_in_play() -> void:
	assert_false(_player.has_anything_in_play())


func test_a_single_owned_commandable_is_enough() -> void:
	_own()
	assert_true(_player.has_anything_in_play())


func test_a_blueprint_alone_does_not_keep_a_commander_alive() -> void:
	# A planned structure needs a builder to become real, and a commander with a builder
	# still has a unit — counting one would mean "you are alive because you have a plan".
	_own(true)
	assert_false(_player.has_anything_in_play(), "a blueprint is not a presence on the map")


func test_a_dying_entity_stops_counting_the_frame_it_dies() -> void:
	# Entity._on_death calls queue_free(), which is END OF FRAME: the dying entity is still
	# its commander's child for the rest of this frame. Without the is_queued_for_deletion
	# filter the whole check resolves a frame late.
	var last: Commandable = _own()
	last.queue_free()
	assert_true(last.is_queued_for_deletion(), "queue_free marks it immediately")
	assert_false(_player.has_anything_in_play(), "and it stops counting immediately")


func test_a_scout_does_not_keep_a_wiped_out_commander_alive() -> void:
	# EventRevealRegion (clears_fog) and EventRadarScan park a Scout under the commander,
	# and a permanent Scan 3 eye would otherwise make its owner immortal — the opponent
	# would have to hunt a drone in a far corner to finish a match already decided.
	#
	# The Scout used to be excluded because it was an Entity rather than a Commandable.
	# It IS one now (that is what made it shootable), so the exclusion moved to the rule
	# that was doing the real work all along: a piece the player cannot SELECT is a piece
	# they cannot command, and cannot be what is keeping them in the game.
	#
	# Built here rather than loaded from scout.tscn so this tests the RULE. That the drone
	# actually clears its layer is test_ReconDrone's business.
	var drone: Commandable = _own()
	var selectable := Selectable.new()
	selectable.name = "Selectable"
	selectable.selectable_by_player = false  # exactly what scout.tscn does
	drone.add_child(selectable)
	drone.selectable = selectable
	assert_false(_player.has_anything_in_play())


# --- Scenario's armed poll ----------------------------------------------------


func test_owning_nothing_at_the_start_is_not_a_defeat() -> void:
	# Skirmish._spawn_initial_entities defers the opening force to navmesh_ready, so every
	# commander owns nothing for the first frames of a match. An unarmed check would lose
	# the game before it started.
	for i: int in 10:
		_tick()
	assert_false(_scenario._game_over_seen, "the match has not started yet")


func test_losing_everything_after_deploying_is_a_defeat() -> void:
	var army: Commandable = _own()
	_tick()
	assert_false(_scenario._game_over_seen, "still in play")

	army.queue_free()
	_tick()
	assert_true(_scenario._game_over_seen, "wiped out")


func test_the_defeat_is_announced_once_and_does_not_reopen() -> void:
	var army: Commandable = _own()
	_tick()
	army.queue_free()
	_tick()
	assert_true(_scenario._game_over_seen)

	# A verdict is final: whatever happens next — a stray spawn, an authored EventWinLose —
	# must not un-lose the game.
	_own()
	_tick()
	assert_true(_scenario._game_over_seen, "the first verdict stands")


func test_a_spectator_session_is_never_eliminated() -> void:
	# No human slot, so PLAYER_COMMANDER_ID stays at its 0 default and there is nobody to
	# lose. Nothing here owns anything, which would otherwise read as an instant defeat.
	RTSController.PLAYER_COMMANDER_ID = 0
	assert_null(_scenario.local_player())
	for i: int in 10:
		_tick()
	assert_false(_scenario._game_over_seen)


func test_a_blueprint_is_not_a_stay_of_execution() -> void:
	# The one place the blueprint rule actually decides a game: last builder dies with a
	# structure still planned.
	var builder: Commandable = _own()
	_own(true)
	_tick()
	assert_false(_scenario._game_over_seen)

	builder.queue_free()
	_tick()
	assert_true(_scenario._game_over_seen, "an unbuildable plan is not a foothold")


# --- Commander.has_production_base --------------------------------------------
# The second half of the rule: no structures and no production is a defeat, whatever units
# are still walking around. See Commander.has_production_base for why.


func test_units_alone_are_not_a_production_base() -> void:
	_own()
	_own()
	assert_true(_player.has_anything_in_play(), "the units are in play")
	assert_false(_player.has_production_base(), "but there is no base behind them")


func test_one_structure_is_a_production_base() -> void:
	_own_structure()
	assert_true(_player.has_production_base())


func test_a_planned_structure_is_not_a_production_base() -> void:
	# Same rule as has_anything_in_play: a blueprint is not a foothold. What keeps a
	# rebuilding commander alive is the QUEUE entry funding it, tested below.
	_own_structure(true)
	assert_false(_player.has_production_base())


func test_a_purchase_still_on_the_queue_is_a_production_base() -> void:
	# The comeback case the structure count alone would cut off: every building gone, but a
	# funded Build in flight with a builder walking to the site.
	_own()
	_player.production_queue.entries.append(PurchaseTransaction.new())
	assert_true(_player.has_production_base())


func test_a_dying_structure_stops_counting_the_frame_it_dies() -> void:
	var last: Commandable = _own_structure()
	last.queue_free()
	assert_false(_player.has_production_base(), "queue_free counts immediately here too")


# --- The base rule inside Scenario's poll -------------------------------------


func test_losing_the_last_structure_is_a_defeat_even_with_units_alive() -> void:
	var base: Commandable = _own_structure()
	var army: Commandable = _own()
	_tick()
	assert_false(_scenario._game_over_seen, "a base and an army is not a defeat")

	base.queue_free()
	_tick()
	assert_true(
		_scenario._game_over_seen,
		"no structures and no production is a defeat, and the surviving unit does not save it"
	)
	assert_true(is_instance_valid(army), "the unit is still alive — that is the point")


func test_a_scenario_that_never_gives_a_base_is_not_lost_on_frame_one() -> void:
	# A mission that opens with units and asks the player to build. The base rule must not
	# arm until there IS a base to lose, or such a scenario is unplayable.
	_own()
	for i: int in 10:
		_tick()
	assert_false(_scenario._game_over_seen)


func test_a_rebuild_in_flight_holds_the_verdict_off() -> void:
	# The half of the rule that is about PRODUCTION rather than structures: the last building
	# is gone, but a purchase is funded and a builder is on its way.
	var base: Commandable = _own_structure()
	_own()
	_tick()
	base.queue_free()
	_player.production_queue.entries.append(PurchaseTransaction.new())
	_tick()
	assert_false(_scenario._game_over_seen, "a purchase in flight is a base being rebuilt")

	_player.production_queue.entries.clear()
	_tick()
	assert_true(_scenario._game_over_seen, "and when it lapses, the verdict lands")


# --- HEGEMONY: the command centre decides -------------------------------------------------


func _own_command_centre(a_commander: Commander = _player) -> Commandable:
	var centre := Commandable.new()
	centre.id = Deployment.command_centre_ids()[0]
	var structure := Structure.new()
	structure.name = "Structure"
	centre.add_child(structure)
	a_commander.add_child(centre)
	return centre


func test_the_default_win_condition_is_mission() -> void:
	assert_eq(_scenario.win_condition, Scenario.WinCondition.MISSION)


func test_hegemony_does_not_eliminate_before_a_command_centre_is_placed() -> void:
	_scenario.win_condition = Scenario.WinCondition.HEGEMONY
	_own()
	_tick()
	assert_false(_player.is_eliminated, "the opening: no centre placed yet is not a defeat")
	assert_false(_scenario._game_over_seen)


func test_hegemony_eliminates_a_commander_whose_last_command_centre_is_gone() -> void:
	_scenario.win_condition = Scenario.WinCondition.HEGEMONY
	var centre: Commandable = _own_command_centre()
	_own()  # a unit that survives the centre
	_tick()
	assert_false(_player.is_eliminated, "armed, and still standing")
	centre.free()
	_tick()
	assert_true(_player.is_eliminated)
	assert_true(_scenario._game_over_seen, "the local player's elimination is the loss")


func test_hegemony_removes_an_eliminated_rival_and_hands_the_player_the_win() -> void:
	_scenario.win_condition = Scenario.WinCondition.HEGEMONY
	var rival := Commander.new()
	rival.id = 2
	_scenario.commanders = [_scenario.commanders[0], _player, rival]
	_own_command_centre()
	var rival_centre: Commandable = _own_command_centre(rival)
	var rival_unit := Commandable.new()
	rival.add_child(rival_unit)
	_tick()
	assert_false(rival.is_eliminated)
	rival_centre.free()
	_tick()
	assert_true(rival.is_eliminated, "no centre left: removed from the match")
	assert_true(rival_unit.is_queued_for_deletion(), "and its pieces leave play")
	assert_true(_scenario._game_over_seen, "every rival gone is the player's win")


func test_a_blueprint_is_not_a_command_centre() -> void:
	_scenario.win_condition = Scenario.WinCondition.HEGEMONY
	var planned: Commandable = _own_command_centre()
	planned.is_planned = true
	_tick()
	assert_false(_player.is_eliminated)
	assert_false(_scenario._hegemony_armed.get(_player.id, false), "a plan does not arm the rule")


func test_none_never_ends_the_match() -> void:
	_scenario.win_condition = Scenario.WinCondition.NONE
	var unit: Commandable = _own()
	_tick()
	unit.free()
	_tick()
	assert_false(_scenario._game_over_seen, "wiped out, and the match runs on")
