extends GutTest

## UPGRADE UNLOCKS: an upgrade's `unlocks:` effect keeps one piece's ability locked until the
## commander owns the upgrade (gdd/systems/macroeconomics/upgrades.md §What an upgrade can
## change). PERMISSION, not capability: the pool still grants the ability throughout.
##
## Every upgrade and piece here is a fixture, never the shipped Cell Activation doc.

const GATE: StringName = &"fake_gate"
const PLANTER: StringName = &"fake_planter"
const HOLDER: StringName = &"fake_holder"
const SPOTTER_OPTIONS: Dictionary = {"abilities": [{"grants": [&"spot"]}]}

var _saved_entries: Dictionary
var _commander: Commander


func before_each() -> void:
	_saved_entries = UpgradeCatalog._entries.duplicate(true)
	UpgradeCatalog._entries[GATE] = {
		"title": "Fake Gate",
		"modifies":
		[{"piece": String(PLANTER), "ability": String(Spot.ABILITY_ID), "unlocks": true}],
	}
	FakePieces.install_ability(Spot.ABILITY_ID, {"range": 10.0, "command": "command_spot"})
	_commander = Commander.new()
	_commander.id = 1
	add_child_autofree(_commander)


func after_each() -> void:
	UpgradeCatalog._entries = _saved_entries
	FakePieces.restore_abilities()


func _owned(a_id: StringName) -> Actor:
	var piece: Actor = FakePieces.make(SPOTTER_OPTIONS)
	_commander.add_child(piece)
	autofree(piece)
	piece.ownership.commander = _commander
	piece.id = a_id
	return piece


func _spot_at_origin() -> CommandMessage:
	return CommandMessage.new(null, null, null, Vector3.ZERO)


func test_a_gated_ability_is_locked_until_the_upgrade_is_owned() -> void:
	var planter: Actor = _owned(PLANTER)
	assert_false(UpgradeCatalog.is_ability_unlocked(planter, Spot.ABILITY_ID))
	_commander.complete_upgrade(GATE)
	assert_true(UpgradeCatalog.is_ability_unlocked(planter, Spot.ABILITY_ID))


func test_the_gate_leaves_other_pieces_granting_the_ability_alone() -> void:
	var holder: Actor = _owned(HOLDER)
	assert_true(UpgradeCatalog.is_ability_unlocked(holder, Spot.ABILITY_ID))


func test_a_locked_spotter_is_refused_with_its_own_cause() -> void:
	var planter: Actor = _owned(PLANTER)
	assert_eq(
		Spot.meets_precondition(planter, _spot_at_origin()),
		MoveCommand.PreconditionFailureCause.MISSING_UPGRADE
	)
	_commander.complete_upgrade(GATE)
	assert_eq(
		Spot.meets_precondition(planter, _spot_at_origin()),
		MoveCommand.PreconditionFailureCause.NONE
	)


func test_a_locked_spotter_still_grants_the_ability() -> void:
	# Capability is kept so the button stays on the card, drawn LOCKED.
	var planter: Actor = _owned(PLANTER)
	assert_true((planter.get_node("Abilities") as Abilities).grants(Spot.ABILITY_ID))


func test_a_selection_of_locked_spotters_draws_the_button_locked() -> void:
	var planter: Actor = _owned(PLANTER)
	var state := CommandButtonState.of("command_spot", [planter], _commander, false)
	assert_eq(state.blocker, CommandButtonState.Blocker.LOCKED)


func test_a_locked_selection_does_not_borrow_an_unlocked_casters_pool() -> void:
	# The commander also owns an unlocked spotter; the selected locked one must not light up
	# through the commander-wide fallback.
	_owned(HOLDER)
	var planter: Actor = _owned(PLANTER)
	var state := CommandButtonState.of("command_spot", [planter], _commander, false)
	assert_eq(state.blocker, CommandButtonState.Blocker.LOCKED)


func test_a_mixed_selection_speaks_for_its_unlocked_caster() -> void:
	var holder: Actor = _owned(HOLDER)
	var planter: Actor = _owned(PLANTER)
	var state := CommandButtonState.of("command_spot", [planter, holder], _commander, false)
	assert_eq(state.blocker, CommandButtonState.Blocker.NONE)


func test_research_lights_the_locked_selection() -> void:
	var planter: Actor = _owned(PLANTER)
	_commander.complete_upgrade(GATE)
	var state := CommandButtonState.of("command_spot", [planter], _commander, false)
	assert_eq(state.blocker, CommandButtonState.Blocker.NONE)
