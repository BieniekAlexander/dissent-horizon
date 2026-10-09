extends GutTest

## ALLIANCES: FIXED TEAMS THAT TURN "YOURS" INTO "YOURS OR AN ALLY'S" WHERE IT IS MEANT TO.
##
## Run with:
## godot --headless --fixed-fps 30 -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_Alliances.gd -gexit
##
## What allies share: not being enemies (aggro, the physics hostile mask, capture), vision,
## repair, and friendly-target abilities. What they do not: orders, garrisons, passive bonuses.
## HEGEMONY removes players one at a time and judges the match per alliance.
## Why: gdd/systems/combat/target-acquisition.md §Alliances.
##
## PATHS, not preloads (see CLAUDE.md).

const SOLDIER: Dictionary = FakePieces.SOLDIER
const MACHINE: Dictionary = FakePieces.MACHINE
const REPAIRER: Dictionary = {"speed": 2.0, "vision": 8.0, "repairs": true}
const GROUND: int = CollisionLayers.Mask.TARGETABLE_GROUND

const ME: int = 1
const ALLY: int = 2
const FOE: int = 3

## Commander ids → bits, the shape Commander.set_alliance takes.
const TEAM_BITS: int = (1 << ME) | (1 << ALLY)

var _me: Commander
var _ally: Commander
var _foe: Commander


func before_each() -> void:
	Fog._fogs_by_commander.clear()
	_me = _commander(ME)
	_ally = _commander(ALLY)
	_foe = _commander(FOE)
	_me.set_alliance(0, TEAM_BITS)
	_ally.set_alliance(0, TEAM_BITS)
	_foe.set_alliance(1, 1 << FOE)


func after_each() -> void:
	Fog._fogs_by_commander.clear()


func _commander(a_id: int) -> Commander:
	var c := Commander.new()
	c.id = a_id
	add_child_autofree(c)
	return c


func _unit(a_options: Dictionary, a_owner: Commander, a_at: Vector3 = Vector3.ZERO) -> Actor:
	var u := FakePieces.make(a_options) as Actor
	add_child_autofree(u)
	u.ownership.commander = a_owner
	u.global_position = a_at
	return u


func _slot(a_team: int) -> PlayerSlot:
	var slot := PlayerSlot.new()
	slot.alliance = a_team
	return slot


# --- Assigning alliances --------------------------------------------------------------------


func test_teamless_slots_are_a_free_for_all() -> void:
	var slots: Array = [_slot(0), _slot(0), _slot(0)]
	assert_eq(Array(Scenario.alliance_indices(slots)), [0, 1, 2])


func test_slots_naming_one_team_share_an_alliance() -> void:
	var slots: Array = [_slot(2), _slot(1), _slot(2), _slot(1)]
	assert_eq(Array(Scenario.alliance_indices(slots)), [0, 1, 0, 1])


func test_a_teamless_slot_never_lands_in_a_team() -> void:
	var slots: Array = [_slot(0), _slot(1), _slot(0), _slot(1)]
	assert_eq(Array(Scenario.alliance_indices(slots)), [0, 1, 2, 1])


func test_eight_teamless_slots_use_all_eight_alliances() -> void:
	var slots: Array = []
	for i: int in Commander.NUM_MAX_COMMANDERS:
		slots.append(_slot(0))
	var indices: Array = Array(Scenario.alliance_indices(slots))
	assert_eq(indices.max(), Commander.NUM_MAX_COMMANDERS - 1)
	assert_eq(PlayerSlot.NUM_TEAMS, Commander.NUM_MAX_COMMANDERS - 1, "a team game offers 1-7")


# --- The side predicates --------------------------------------------------------------------


func test_a_commander_is_allied_with_itself_and_its_team_only() -> void:
	assert_true(_me.is_allied_with(ME))
	assert_true(_me.is_allied_with(ALLY))
	assert_false(_me.is_allied_with(FOE))
	assert_false(_me.is_allied_with(0), "neutral is nobody's ally")
	assert_true(_me.shares_side_with(ALLY))


func test_a_commander_no_scenario_placed_is_alone() -> void:
	var lone: Commander = _commander(5)
	assert_true(lone.is_allied_with(5))
	assert_false(lone.is_allied_with(ME))
	assert_eq(lone.allied_ids_mask(), 1 << 5)


func test_an_ally_is_friendly_and_never_an_enemy() -> void:
	var mine: Actor = _unit(SOLDIER, _me)
	var theirs: Actor = _unit(SOLDIER, _ally)
	var hostile: Actor = _unit(SOLDIER, _foe)
	assert_true(mine.is_friendly_to(theirs))
	assert_false(mine.is_enemy_of(theirs))
	assert_true(mine.is_enemy_of(hostile))
	assert_false(theirs.is_friendly_to(hostile))


func test_the_hostile_mask_leaves_out_every_ally() -> void:
	var mask: int = CollisionLayers.hostile_mask(GROUND, _me.allied_ids_mask())
	assert_eq(mask & CollisionLayers.side_bits(GROUND, ME), 0)
	assert_eq(mask & CollisionLayers.side_bits(GROUND, ALLY), 0, "an ally is not hostile")
	assert_ne(mask & CollisionLayers.side_bits(GROUND, FOE), 0)


func test_an_allied_crowd_never_fills_the_aggro_scan() -> void:
	# The enemy is created first: the physics query is newest-first, so an unfiltered capped
	# scan would return only the allies ringed closer in (test_AggroIgnoresAllies, widened).
	var enemy: Actor = _unit(FakePieces.BUILDER, _foe, Vector3(3.0, 0.0, 0.0))
	var shooter: Actor = _unit(SOLDIER, _me)
	for i: int in 16:
		var angle: float = TAU * i / 16.0
		_unit(SOLDIER, _ally, Vector3(cos(angle), 0.0, sin(angle)) * 1.5)
	await wait_physics_frames(2)
	var found: Array[Entity] = shooter.hostiles_in_aggro(Actor.AGGRO_SCAN_MAX_RESULTS)
	assert_eq(found, [enemy] as Array[Entity])


func test_stealth_hides_nothing_from_its_own_side() -> void:
	var cloaked: Actor = _unit({"speed": 2.0, "vision": 8.0, "stealth": true}, _ally)
	cloaked.stealth.state = Stealth.State.STEALTHED
	assert_true(cloaked.is_visible_to(ME), "an ally sees through it")
	assert_false(cloaked.is_visible_to(FOE))


# --- Shared vision --------------------------------------------------------------------------


func _fog_for(a_viewer: int) -> Fog:
	var fog := Fog.new()
	fog.watching_commander_id = a_viewer
	add_child_autofree(fog)
	fog.set_physics_process(false)
	fog._configure(48, 48, Vector2.ZERO, 24.0, 24.0)
	return fog


func test_an_allys_sight_clears_this_commanders_fog() -> void:
	var fog: Fog = _fog_for(ME)
	var there := Vector3(10.0, 0.0, 10.0)
	_unit(SOLDIER, _ally, there)
	fog._update_sight(get_tree().get_nodes_in_group("los"))
	assert_true(fog.fog_clear_at(VU.in_xz(there)))


func test_an_enemys_sight_does_not() -> void:
	var fog: Fog = _fog_for(ME)
	var there := Vector3(10.0, 0.0, 10.0)
	_unit(SOLDIER, _foe, there)
	fog._update_sight(get_tree().get_nodes_in_group("los"))
	assert_false(fog.fog_clear_at(VU.in_xz(there)))


# --- What allies may do for each other ------------------------------------------------------


func test_an_allys_damaged_machine_can_be_repaired() -> void:
	var mechanic: Actor = _unit(REPAIRER, _me)
	var tank: Actor = _unit(MACHINE, _ally)
	tank.defense.hp = tank.defense.hp_max * 0.5
	assert_true(Repair.can_repair(mechanic, tank))


func test_an_enemys_damaged_machine_cannot() -> void:
	var mechanic: Actor = _unit(REPAIRER, _me)
	var tank: Actor = _unit(MACHINE, _foe)
	tank.defense.hp = tank.defense.hp_max * 0.5
	assert_false(Repair.can_repair(mechanic, tank))


func test_a_friendly_target_ability_accepts_an_allys_unit() -> void:
	var event: EventTargetUnit = autofree(EventTargetUnit.new())
	event.scope = EventTargetUnit.Scope.OWN
	assert_true(event.accepts(_unit(SOLDIER, _ally), ME))
	assert_false(event.accepts(_unit(SOLDIER, _foe), ME))


func test_dignify_takes_only_the_casters_own_irregulars() -> void:
	var event: EventDignify = autofree(EventDignify.new())
	event.scope = EventTargetUnit.Scope.OWN
	var builder: Dictionary = FakePieces.BUILDER.duplicate()
	builder["id"] = EntityIds.AN_BIO_LIGHT_BUILDER
	assert_true(event.accepts(_unit(builder, _me), ME))
	assert_false(event.accepts(_unit(builder, _ally), ME), "the Warlord would be the caster's")


func test_the_heal_aura_mends_an_allys_infantry_but_not_an_enemys() -> void:
	var clinic: Actor = _unit(FakePieces.BUILDING, _me)
	var aura := HealAOE.new()
	clinic.add_child(aura)
	assert_true(aura.heals(_unit(SOLDIER, _me)))
	assert_true(aura.heals(_unit(SOLDIER, _ally)), "the BIO counterpart of Repair")
	assert_false(aura.heals(_unit(SOLDIER, _foe)))
	assert_false(aura.heals(_unit(MACHINE, _ally)), "machines are Repair's")


func test_allies_cannot_capture_each_other() -> void:
	var truck: Actor = _unit(FakePieces.TRUCK, _me)
	assert_false(Garrison.can_capture(truck, _unit(FakePieces.BUILDER, _ally)))
	assert_true(Garrison.can_capture(truck, _unit(FakePieces.BUILDER, _foe)))


# --- HEGEMONY, per alliance -----------------------------------------------------------------
# Out of the tree, as test_Elimination drives it: Scenario._ready is not what is under test.


class Match:
	extends RefCounted
	var scenario: Scenario
	var commanders: Array = []

	func free_all() -> void:
		for c: Commander in commanders:
			c.free()
		scenario.free()


## A HEGEMONY scenario of `a_teams` (one entry per player slot, 0 = no team), every player armed
## with a command centre, the local player commander 1.
func _match(a_teams: Array) -> Match:
	var m := Match.new()
	m.scenario = Scenario.new()
	m.scenario.win_condition = Scenario.WinCondition.HEGEMONY
	var neutral := Commander.new()
	neutral.id = 0
	m.commanders.append(neutral)
	var slots: Array = []
	for team: int in a_teams:
		slots.append(_slot(team))
	var indices: PackedInt32Array = Scenario.alliance_indices(slots)
	for i: int in a_teams.size():
		var c := Commander.new()
		c.id = i + 1
		m.commanders.append(c)
	for i: int in a_teams.size():
		var bits: int = 0
		for j: int in a_teams.size():
			if indices[j] == indices[i]:
				bits |= 1 << (j + 1)
		(m.commanders[i + 1] as Commander).set_alliance(indices[i], bits)
		_centre(m.commanders[i + 1])
	m.scenario.commanders = m.commanders
	return m


func _centre(a_commander: Commander) -> Actor:
	var centre := Actor.new()
	centre.id = Deployment.command_centre_ids()[0]
	var fixture := Fixture.new()
	fixture.name = "Fixture"
	centre.add_child(fixture)
	a_commander.add_child(centre)
	return centre


func _destroy_centres(a_commander: Commander) -> void:
	for child: Node in a_commander.get_children():
		child.free()


func _with_player(a_body: Callable) -> void:
	var saved: int = RTSController.PLAYER_COMMANDER_ID
	RTSController.PLAYER_COMMANDER_ID = 1
	a_body.call()
	RTSController.PLAYER_COMMANDER_ID = saved


func test_losing_my_centres_with_an_ally_standing_is_not_yet_a_defeat() -> void:
	var m: Match = _match([1, 1, 2, 2])
	_with_player(
		func() -> void:
			m.scenario._physics_process(0.0)
			_destroy_centres(m.commanders[1])
			m.scenario._physics_process(0.0)
			assert_true((m.commanders[1] as Commander).is_eliminated, "removed as a player")
			assert_false(m.scenario._game_over_seen, "the team plays on, and I keep watching")
	)
	m.free_all()


func test_the_last_of_my_team_going_is_the_defeat() -> void:
	var m: Match = _match([1, 1, 2, 2])
	_with_player(
		func() -> void:
			m.scenario._physics_process(0.0)
			_destroy_centres(m.commanders[1])
			_destroy_centres(m.commanders[2])
			m.scenario._physics_process(0.0)
			assert_true(m.scenario._game_over_seen)
	)
	m.free_all()


func test_the_win_needs_every_rival_alliance_gone() -> void:
	var m: Match = _match([1, 1, 2, 2])
	_with_player(
		func() -> void:
			m.scenario._physics_process(0.0)
			_destroy_centres(m.commanders[3])
			m.scenario._physics_process(0.0)
			assert_false(m.scenario._game_over_seen, "one rival is left")
			_destroy_centres(m.commanders[4])
			m.scenario._physics_process(0.0)
			assert_true(m.scenario._game_over_seen)
	)
	m.free_all()


func test_a_team_wins_with_its_eliminated_member() -> void:
	var m: Match = _match([1, 1, 2])
	_with_player(
		func() -> void:
			m.scenario._physics_process(0.0)
			_destroy_centres(m.commanders[1])
			m.scenario._physics_process(0.0)
			_destroy_centres(m.commanders[3])
			m.scenario._physics_process(0.0)
			assert_true(m.scenario._game_over_seen)
			assert_eq(m.scenario.alliance_of(2), [1, 2], "the winners are the whole team")
			assert_eq(m.scenario._match_summary_title(2), "Victory")
	)
	m.free_all()


func test_teammates_are_not_rivals() -> void:
	var m: Match = _match([1, 1])
	_with_player(
		func() -> void:
			m.scenario._physics_process(0.0)
			assert_eq(m.scenario._rivals(), 0)
			assert_false(m.scenario._game_over_seen, "a session with no rival never wins")
	)
	m.free_all()


func test_a_match_log_names_every_winner() -> void:
	var match_log: MatchLog = autofree(MatchLog.new())
	match_log.end(2, [1, 2])
	assert_eq(MatchSummary.winner(match_log.events), 2)
	assert_eq(MatchSummary.winners(match_log.events), [1, 2])


func test_a_log_from_before_alliances_still_names_its_winner() -> void:
	var events: Array = [{"type": MatchLog.MATCH_ENDED, "winner": 3}]
	assert_eq(MatchSummary.winners(events), [3])
