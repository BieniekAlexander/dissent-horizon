extends GutTest

## Carrying a unit's standing orders across a TRANSFORMATION (Dignify: an Irregular
## becomes a Warlord). The chain is walked and TRUNCATED at the first command the new
## piece cannot perform — see CommandReceiver.portable_chain_for for why truncating
## beats filtering.
##
## The Irregular / Warlord pair is the real case and is used directly rather than
## mocked: the Irregular carries a Builds component and the Warlord does not, which is
## exactly the capability gap the rule exists for.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_UnitTransformation.gd -gexit

const IRREGULAR: PackedScene = preload("res://scenes/entities/units/an/an_bioLight_builder.tscn")
const WARLORD: PackedScene = preload("res://scenes/entities/units/an/an_bioMedium_dominionGen.tscn")


func _unit(a_scene: PackedScene) -> Commandable:
	var unit: Commandable = a_scene.instantiate()
	add_child_autofree(unit)
	unit.top_level = true
	return unit


## A CommandMessage needs a Map; these commands are never executed, only inspected for
## which capability they represent, so a bare one is enough.
func _message() -> CommandMessage:
	return CommandMessage.new(null, null, null, Vector3(4.0, 0.0, 6.0))


# --- The name mapping the rule is built on --------------------------------------

func test_a_command_reports_the_name_the_rules_table_uses() -> void:
	# CommandContextParser.commands_for speaks in names; a live command has to be
	# translatable into one or the capability question cannot be asked at all.
	assert_eq(CommandContextParser.name_for(Build.new(_message())), "command_build")
	assert_eq(CommandContextParser.name_for(MoveCommand.new(_message())), "command_move")


func test_an_unnamed_command_is_treated_as_portable() -> void:
	# Wander is not offered as a player capability, so there is no capability question to
	# ask about it. It must not be mistaken for "this actor cannot do it".
	var wander := Wander.new(_message())
	assert_eq(CommandContextParser.name_for(wander), "")
	assert_true(CommandContextParser.actor_can_perform(_unit(WARLORD), wander))


# --- Capability -----------------------------------------------------------------

func test_a_warlord_cannot_build_but_an_irregular_can() -> void:
	var build := Build.new(_message())
	assert_true(CommandContextParser.actor_can_perform(_unit(IRREGULAR), build),
		"the Irregular carries a Builds component")
	assert_false(CommandContextParser.actor_can_perform(_unit(WARLORD), build),
		"the Warlord does not")


func test_both_can_move() -> void:
	var move := MoveCommand.new(_message())
	assert_true(CommandContextParser.actor_can_perform(_unit(IRREGULAR), move))
	assert_true(CommandContextParser.actor_can_perform(_unit(WARLORD), move))


# --- The chain ------------------------------------------------------------------

func _queue(a_unit: Commandable, a_commands: Array[MoveCommand]) -> void:
	a_unit.command_receiver.update_commands(a_commands)


func test_a_fully_portable_chain_survives_intact() -> void:
	var irregular := _unit(IRREGULAR)
	_queue(irregular, [MoveCommand.new(_message()), MoveCommand.new(_message())])
	var carried := irregular.command_receiver.portable_chain_for(_unit(WARLORD))
	assert_eq(carried.size(), 2, "nothing a Warlord cannot do, so nothing is dropped")


func test_the_chain_truncates_at_the_first_impossible_command() -> void:
	# Move, Build, Move — the Warlord keeps only the leading Move. The Move AFTER the
	# Build is dropped too: it was issued expecting the building to exist.
	var irregular := _unit(IRREGULAR)
	_queue(irregular, [
		MoveCommand.new(_message()), Build.new(_message()), MoveCommand.new(_message()),
	])
	var carried := irregular.command_receiver.portable_chain_for(_unit(WARLORD))
	assert_eq(carried.size(), 1, "everything from the Build onward is dropped")
	assert_true(carried[0] is MoveCommand)
	assert_false(carried[0] is Build)


func test_a_leading_impossible_command_carries_nothing() -> void:
	var irregular := _unit(IRREGULAR)
	_queue(irregular, [Build.new(_message()), MoveCommand.new(_message())])
	assert_eq(irregular.command_receiver.portable_chain_for(_unit(WARLORD)).size(), 0)


func test_an_idle_unit_carries_an_empty_chain() -> void:
	var irregular := _unit(IRREGULAR)
	assert_eq(irregular.command_receiver.portable_chain_for(_unit(WARLORD)).size(), 0)


func test_the_carried_commands_are_copies() -> void:
	# The old unit is about to be freed and its teardown releases whatever its live
	# command instances were holding, so the new unit must not share them.
	var irregular := _unit(IRREGULAR)
	var original := MoveCommand.new(_message())
	_queue(irregular, [original])
	var carried := irregular.command_receiver.portable_chain_for(_unit(WARLORD))
	assert_eq(carried.size(), 1)
	assert_ne(carried[0], original, "a fresh instance, not the live one")
	assert_ne(carried[0].message, original.message, "with its own message")
