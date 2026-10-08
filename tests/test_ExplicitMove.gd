extends GutTest

## The "Go" order — a move the right-click resolution is not allowed to reinterpret.
##
## Every other route to a plain move is the FALLBACK at the bottom of
## RTSController._resolve_command_class, which anything more specific takes first. That made
## two orders inexpressible: driving a truck THROUGH an enemy (there is no crush command —
## crushing is what happens when it arrives) and shadowing an enemy with a scout without
## opening fire. Arming `command_move` suppresses the whole ladder for one click.
##
## Pieces are fakes (tests/_fake_pieces.gd), not shipped scenes.

## A mobile piece with a gun: the stand-in for "a soldier".
const SHOOTER: Dictionary = {"speed": 2.0, "weapon": {"ground": 6.0}}


func _commanded(a_id: int) -> Commander:
	var c := Commander.new()
	c.id = a_id
	add_child_autofree(c)
	return c


func _entity(a_options: Dictionary, a_commander_id: int) -> Actor:
	var e: Actor = FakePieces.unit(a_options)
	add_child_autofree(e)
	e.ownership.commander = _commanded(a_commander_id)
	return e


func _resolved(a_pending: String, a_actor: Actor, a_target: Entity) -> Variant:
	return RTSController.resolve_command_class_for_selection(
		a_pending, [a_actor], CommandMessage.new(null, a_target)
	)


#region Resolution
func test_an_enemy_under_the_cursor_is_normally_an_attack() -> void:
	var soldier: Actor = _entity(SHOOTER, 1)
	var enemy: Actor = _entity(SHOOTER, 2)
	assert_eq(_resolved("", soldier, enemy), Attack, "the default right-click")


func test_arming_go_makes_the_same_click_a_move() -> void:
	var soldier: Actor = _entity(SHOOTER, 1)
	var enemy: Actor = _entity(SHOOTER, 2)
	assert_eq(_resolved("command_move", soldier, enemy), MoveCommand)


func test_go_at_bare_ground_is_still_a_move() -> void:
	assert_eq(_resolved("command_move", _entity(SHOOTER, 1), null), MoveCommand)


## A move at a friendly unit is a FOLLOW — the receiver makes that of it, not the command
## (see CommandReceiver._follow_target) — so "shadow that unit" needs no command of its own.
func test_go_keeps_the_target_so_the_receiver_can_follow_it() -> void:
	var soldier: Actor = _entity(SHOOTER, 1)
	var enemy: Actor = _entity(SHOOTER, 2)
	var message := CommandMessage.new(null, enemy)
	var command := MoveCommand.new(message)
	assert_eq(command.message.target, enemy)


#endregion


#region The grid
func test_go_has_a_button_and_a_key() -> void:
	var binding: ControlBinding = CommandGrid.binding_for("command_move")
	assert_not_null(binding, "Go is in the grid")
	assert_eq(binding.label, "Go")
	assert_eq(binding.grid_position.y, 1, "it is a generic verb, so it sits in the verb row")
	assert_eq(InputPrompt.action_text(CommandGrid.action_for_command("command_move")), "G")


## Every unit that can walk, and every producer (whose plain move is its rally point),
## already advertises `command_move` — so the button is on show wherever the order means
## something, with no new capability rule to keep in step.
func test_the_capability_was_already_there() -> void:
	assert_true(CommandContextParser.commands_for(_entity(SHOOTER, 1)).has("command_move"))
#endregion
