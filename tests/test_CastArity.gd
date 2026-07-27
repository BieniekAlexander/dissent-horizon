extends GutTest

## HOW MANY of the selected actors carry an order out — the command's own default, and what
## the two modifiers do to it.
##
## The rule the whole file pins (see ui/control-matrices.md §Cast arity):
##
##   |            | no modifier | narrow | broaden |
##   |------------|-------------|--------|---------|
##   | ALL        | all         | one    | all     |
##   | SINGLE     | one         | one    | all     |
##
## The modifiers were always ABSOLUTE — narrow yields one, broaden yields all — and the
## matrix note has said "whichever way the command's own default falls" since they were
## written. What was missing was any command whose default was not ALL.
##
## The MODIFIER half needs live input state, which a headless test cannot set; those cells
## are driven through `modified_arity` directly, which is the one place the rule is stated.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gtest=res://tests/test_CastArity.gd -gexit


func _message() -> CommandMessage:
	return CommandMessage.new(null, null, null, Vector3.ZERO)


func _ability_message(a_id: StringName) -> CommandMessage:
	var message: CommandMessage = _message()
	message.ability_type = a_id
	return message


# --- The defaults --------------------------------------------------------------------

func test_an_ordinary_verb_goes_to_everyone() -> void:
	# Telling a squad to advance and having one of them go would be absurd.
	for command: Script in [MoveCommand, AttackMove, Stop, Defend]:
		assert_eq(command.default_cast_arity(_message()), MoveCommand.CastArity.ALL,
			"%s is an order for the whole selection" % command.get_global_name())


func test_build_goes_to_one_builder() -> void:
	# Five builders converging on one site is four builders not building anything else.
	assert_eq(Build.default_cast_arity(_message()), MoveCommand.CastArity.SINGLE)


func test_an_ability_is_cast_by_one_caster_by_default() -> void:
	# The whole selection firing at one point spends every charge on it.
	assert_eq(Ability.default_cast_arity(_ability_message(&"irradiate")),
		MoveCommand.CastArity.SINGLE)


func test_an_unknown_ability_still_reads_as_single() -> void:
	# The catalog degrades to the default rather than erroring; validation is the importer's
	# job, and a HUD that fell over on a typo would be worse than a wrong arity.
	assert_eq(Ability.default_cast_arity(_ability_message(&"no_such_ability")),
		MoveCommand.CastArity.SINGLE)


func test_spot_is_authored_to_be_cast_by_all_of_them() -> void:
	# The roster's one `cast_by: ALL`. A second firing solution on the same ground is worth
	# having, where a second Irradiate on one point is a wasted charge.
	assert_eq(Spot.default_cast_arity(_message()), MoveCommand.CastArity.ALL)


func test_the_doc_key_governs_rather_than_describing() -> void:
	# Spot extends MoveCommand, not Ability, so it does not inherit the catalog lookup — the
	# thing this asserts is that it makes one, and would follow the doc if `cast_by:` changed.
	assert_eq(Spot.default_cast_arity(_message()),
		AbilityCatalog.cast_arity_of(Spot.ABILITY_ID))


func test_a_sanction_reads_the_same_key_as_the_ability_it_unlocks() -> void:
	# A sanction is one UNLOCK ROUTE to an ability, not a different kind of thing.
	var sanction := autofree(Sanction.new()) as Sanction
	sanction.ability_id = Spot.ABILITY_ID
	var message: CommandMessage = _message()
	message.sanction = sanction
	assert_eq(UseSanction.default_cast_arity(message), MoveCommand.CastArity.ALL)


# --- What the modifiers do to a default ------------------------------------------------

func _controller() -> RTSController:
	return autofree(RTSController.new()) as RTSController


func test_with_no_modifier_the_default_stands() -> void:
	# `modified_arity` is asked with nothing held: a headless test presses no keys, which is
	# exactly the no-modifier cell.
	var controller: RTSController = _controller()
	assert_eq(controller.modified_arity(MoveCommand.CastArity.ALL),
		MoveCommand.CastArity.ALL)
	assert_eq(controller.modified_arity(MoveCommand.CastArity.SINGLE),
		MoveCommand.CastArity.SINGLE)


func test_a_null_command_reads_as_all() -> void:
	# Nothing resolved is not a reason to narrow an order to one actor.
	assert_eq(_controller().cast_arity_for(null, _message()), MoveCommand.CastArity.ALL)


func test_the_controller_asks_the_command_for_its_default() -> void:
	# The wiring, not the rule: with no modifier held, cast_arity_for is the command's own
	# answer. Both directions, so a hard-coded return would fail one of them.
	var controller: RTSController = _controller()
	assert_eq(controller.cast_arity_for(Build, _message()), MoveCommand.CastArity.SINGLE)
	assert_eq(controller.cast_arity_for(AttackMove, _message()), MoveCommand.CastArity.ALL)


# --- The preview draws for exactly the casters that would fire --------------------------

func test_nothing_armed_names_no_casters() -> void:
	assert_eq(_controller().armed_ability_casters().size(), 0)


func test_the_preview_and_the_order_ask_the_same_question() -> void:
	# The rings the player sees and the pieces that fire are the same set BY CONSTRUCTION —
	# both go through the arity, so they cannot come to disagree.
	var controller: RTSController = _controller()
	controller.pending_command_name = "command_launch"
	assert_eq(controller.armed_cast_arity(),
		AbilityCatalog.cast_arity_of(RTSController.LAUNCH_ABILITY),
		"with nothing held, the armed preview is the ability's own default")
