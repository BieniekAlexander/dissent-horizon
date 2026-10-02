extends GutTest

## The single-target sanction payloads: which units each one accepts, and what happens to
## the one it is cast on. All of these run through EventTargetUnit, whose two knobs —
## `scope` (whose units) and `_qualifies` (what else must be true) — are what let one script
## serve Freeze 1 and Freeze 2, or all three Informant tiers, from authored scene data.
##
## A cast NAMES its unit (EventTargetUnit.target_unit); there is no search around a point. So
## the property asserted per payload is: an ineligible unit is not ACCEPTED, and naming one
## does nothing. Finding an eligible unit in a mixed group is the cursor's job, which only
## ever offers units `accepts` passes — see RTSController._update_ability_target.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_SanctionPayloads.gd -gexit

const UNIT_SCENE: Dictionary = FakePieces.BUILDER

const OWN: int = 1
const FOE: int = 2

var _manager: ScenarioTriggerManager
var _commanders: Dictionary = {}  # id -> Commander


func before_each() -> void:
	# The events read the "unit" group through the manager's tree, as the other event
	# tests do. A manager parented to anything but a Scenario warns, which is expected
	# here (see test_EventRevealRegion, same fixture shape).
	_manager = ScenarioTriggerManager.new()
	add_child_autofree(_manager)
	assert_push_warning("expected parent to be Scenario")
	_commanders = {}


func after_each() -> void:
	# An in-tree SimulationClock pauses the WHOLE tree, GUT included.
	if _manager.simulation_clock != null:
		_manager.simulation_clock.clear()
	get_tree().paused = false


## A Commander for `id`, made once per test. Ownership resolves commander_id through a
## real Commander reference, so these payloads' friend/foe tests need actual ones.
func _commander(a_id: int) -> Commander:
	if not _commanders.has(a_id):
		var commander := Commander.new()
		commander.id = a_id
		add_child_autofree(commander)
		_commanders[a_id] = commander
	return _commanders[a_id]


## A real unit — irregular.tscn — rather than a hand-built Commandable: the class hard-
## requires a scene rig (an HP bar, an AvoidanceObstacle, an Ownership) that a bare
## `Commandable.new()` has no way to supply, and assembling a fake one only tests the
## fake. Armour, frame and owner are overridden afterwards, which is all these payloads
## read; the piece it happens to be is irrelevant except to Informant's tier-1
## eligibility, which these tests do not exercise.
func _unit(
	a_commander_id: int,
	a_at: Vector2,
	a_armour: Defense.ArmourType = Defense.ArmourType.LIGHT,
	a_frame: Defense.FrameType = Defense.FrameType.BIO
) -> Commandable:
	var unit: Commandable = FakePieces.make(UNIT_SCENE)
	add_child_autofree(unit)
	unit.top_level = true
	unit.ownership.commander = _commander(a_commander_id)
	unit.defense.armour_type = a_armour
	unit.defense.frame_type = a_frame
	unit.defense.hp_max = 1000.0
	unit.defense.hp = 1000.0
	unit.global_position = Vector3(a_at.x, 0.0, a_at.y)
	return unit


func _run(a_event: EventTargetUnit, a_target: Commandable) -> void:
	add_child_autofree(a_event)
	a_event.commander_id = OWN
	a_event.target_unit = a_target
	a_event.execute(_manager)


# --- Freeze ----------------------------------------------------------------------


func test_freeze_1_takes_only_your_own_units() -> void:
	var mine := _unit(OWN, Vector2(0, 0))
	var theirs := _unit(FOE, Vector2(0.5, 0))
	var event := EventFreeze.new()
	event.scope = EventTargetUnit.Scope.OWN
	assert_false(event.accepts(theirs, OWN), "Freeze 1 may not have an enemy")
	_run(event, theirs)
	assert_false(theirs.is_stunned(), "and naming one does nothing")
	_run(EventFreeze.new(), mine)
	assert_true(mine.is_stunned(), "your own unit is frozen")


func test_freeze_2_takes_anyone() -> void:
	var theirs := _unit(FOE, Vector2(0, 0))
	var event := EventFreeze.new()
	event.scope = EventTargetUnit.Scope.ANY
	_run(event, theirs)
	assert_true(theirs.is_stunned(), "Freeze 2 reaches an enemy")


func test_freeze_refuses_a_strong_unit() -> void:
	var heavy := _unit(OWN, Vector2(0, 0), Defense.ArmourType.STRONG)
	var light := _unit(OWN, Vector2(1.5, 0), Defense.ArmourType.LIGHT)
	var event := EventFreeze.new()
	assert_false(event.accepts(heavy, OWN), "STRONG armour cannot be frozen")
	assert_true(event.accepts(light, OWN))
	_run(event, heavy)
	assert_false(heavy.is_stunned())


func test_a_structure_is_never_a_target() -> void:
	var unit := _unit(OWN, Vector2(0, 0))
	unit.remove_from_group("unit")
	assert_false(EventFreeze.new().accepts(unit, OWN), "only units are single-unit targets")


func test_nothing_named_does_nothing() -> void:
	var unit := _unit(OWN, Vector2(0, 0))
	_run(EventFreeze.new(), null)
	assert_false(unit.is_stunned(), "no search around the aim point any more")


# --- Promotion -------------------------------------------------------------------


func test_promotion_only_takes_an_unblooded_unit() -> void:
	var veteran := _unit(OWN, Vector2(0, 0))
	veteran.veterancy.set_level(Veterancy.Level.VETERAN)
	var rookie := _unit(OWN, Vector2(1.5, 0))
	assert_false(EventPromote.new().accepts(veteran, OWN), "an already-promoted unit is refused")
	_run(EventPromote.new(), rookie)
	assert_eq(rookie.veterancy.level, Veterancy.Level.VETERAN, "the unblooded unit is promoted")


func test_promotion_is_never_a_shortcut_to_heroic() -> void:
	# Firing it twice on one unit must not walk it up the ranks.
	var unit := _unit(OWN, Vector2(0, 0))
	_run(EventPromote.new(), unit)
	_run(EventPromote.new(), unit)
	assert_eq(
		unit.veterancy.level, Veterancy.Level.VETERAN, "the later levels stay earned in combat"
	)


# --- Informant -------------------------------------------------------------------


func test_informant_2_takes_any_bio_unit() -> void:
	var mech := _unit(OWN, Vector2(0, 0), Defense.ArmourType.LIGHT, Defense.FrameType.MECH)
	var bio := _unit(OWN, Vector2(1.5, 0), Defense.ArmourType.LIGHT, Defense.FrameType.BIO)
	var event := EventInformant.new()
	event.eligibility = EventInformant.Eligibility.ANY_BIO
	assert_false(event.accepts(mech, OWN), "a machine is not a target")
	_run(event, bio)
	assert_not_null(bio.get_node_or_null("Stealth"), "the biological unit is stealthed")


func test_informant_3_takes_a_machine_too() -> void:
	var mech := _unit(OWN, Vector2(0, 0), Defense.ArmourType.LIGHT, Defense.FrameType.MECH)
	var event := EventInformant.new()
	event.eligibility = EventInformant.Eligibility.ANY
	_run(event, mech)
	assert_not_null(mech.get_node_or_null("Stealth"))
	assert_not_null(mech.stealth, "Entity.stealth is wired, not just the node added")


func test_informant_refuses_an_already_stealthed_unit() -> void:
	var already := _unit(OWN, Vector2(0, 0))
	var stealth := Stealth.new()
	stealth.name = "Stealth"
	already.add_child(stealth)
	already.stealth = stealth
	var event := EventInformant.new()
	event.eligibility = EventInformant.Eligibility.ANY
	assert_false(event.accepts(already, OWN))


# --- Overcharge ------------------------------------------------------------------


func _stun(a_unit: Commandable) -> void:
	var effect := StunStatusEffect.new()
	effect.affects_frames = Garrison.FRAME_ANY
	effect.duration_ticks = 300
	effect.apply_to(a_unit)


func test_overcharge_only_takes_a_disabled_unit() -> void:
	var awake := _unit(FOE, Vector2(0, 0))
	var disabled := _unit(FOE, Vector2(1.5, 0))
	_stun(disabled)
	var event := EventOvercharge.new()
	event.scope = EventTargetUnit.Scope.ANY
	event.damage = 400.0
	assert_false(event.accepts(awake, OWN), "an undisabled unit is not a target")
	_run(event, disabled)
	assert_eq(disabled.defense.hp, 600.0, "the disabled one takes the surge")


func test_overcharge_does_nothing_to_an_awake_unit() -> void:
	var awake := _unit(FOE, Vector2(0, 0))
	var event := EventOvercharge.new()
	event.scope = EventTargetUnit.Scope.ANY
	_run(event, awake)
	assert_eq(
		awake.defense.hp, 1000.0, "worth nothing on its own — it is the second half of a pair"
	)


func test_overcharge_reaches_a_frozen_unit() -> void:
	# FreezeStatusEffect extends StunStatusEffect, so a frozen unit is as helpless as an
	# EMPed one and qualifies. Accepted cross-faction interaction, not an oversight.
	var frozen := _unit(FOE, Vector2(0, 0))
	FreezeStatusEffect.new().apply_to(frozen)
	var event := EventOvercharge.new()
	event.scope = EventTargetUnit.Scope.ANY
	event.damage = 250.0
	_run(event, frozen)
	assert_eq(frozen.defense.hp, 750.0)


# --- Global EMP ------------------------------------------------------------------


func test_global_emp_stuns_machines_anywhere_on_the_map() -> void:
	var far_mech := _unit(FOE, Vector2(500, 500), Defense.ArmourType.LIGHT, Defense.FrameType.MECH)
	var event := EventGlobalEmp.new()
	add_child_autofree(event)
	event.execute(_manager)
	assert_true(far_mech.is_stunned(), "distance is irrelevant — it is map-wide")


func test_global_emp_spares_infantry_on_both_sides() -> void:
	# The asymmetry IS the mechanic: the Anarchists' army is biological, so they pay
	# almost nothing to fire it.
	var bio := _unit(FOE, Vector2(0, 0), Defense.ArmourType.LIGHT, Defense.FrameType.BIO)
	var event := EventGlobalEmp.new()
	add_child_autofree(event)
	event.execute(_manager)
	assert_false(bio.is_stunned(), "a stun only takes hold on a MECH frame")


func test_global_emp_catches_your_own_machines_too() -> void:
	var mine := _unit(OWN, Vector2(0, 0), Defense.ArmourType.LIGHT, Defense.FrameType.MECH)
	var event := EventGlobalEmp.new()
	add_child_autofree(event)
	# No commander_id is set, and the event has no such field: Global EMP is the one
	# sanction that neither aims nor takes sides.
	event.execute(_manager)
	assert_true(
		mine.is_stunned(), "sparing the caster's own vehicles would erase the cost of firing it"
	)
