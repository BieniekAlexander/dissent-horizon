extends GutTest

## HOLD FIRE — a flag on the piece, never an order.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_HoldFire.gd -gexit
##
## What is pinned: who is offered it (anything with a weapon), how the button toggles it (none
## or some holding sets it for all; all holding releases all), that pressing it leaves the queue
## alone unless the additive modifier queues it, what releases it (Attack, Attack-move, Force
## Fire and Defend, queued or not), that it suppresses the piece's own target acquisition, that
## gaining stealth sets it, that the button is lit — and still pressable — once the whole armed
## selection is holding, and that an unarmed piece holding it draws nothing.


## A Actor with the children Entity/Actor resolve with a hard `$` — the stub shape
## tests/test_BotKamikazeHold.gd uses — optionally carrying a Loadout with one Weapon.
class StubPiece:
	extends Actor

	static func make(a_is_armed: bool) -> StubPiece:
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
		if a_is_armed:
			var loadout := Loadout.new()
			loadout.name = "Loadout"
			var weapon := Weapon.new()
			var reach := CollisionShape3D.new()
			reach.name = "AttackRange"
			weapon.add_child(reach)
			loadout.add_child(weapon)
			piece.add_child(loadout)
		return piece

	func _ready() -> void:
		set_process(false)
		set_physics_process(false)


var _commander: Commander


func before_each() -> void:
	_commander = Commander.new()
	_commander.id = 1
	add_child_autofree(_commander)


func _piece(a_is_armed: bool = true) -> Actor:
	var piece: StubPiece = StubPiece.make(a_is_armed)
	_commander.add_child(piece)
	piece.ownership.commander = _commander
	return piece


func _attack(a_target: Actor) -> Attack:
	return Attack.new(CommandMessage.new(null, a_target))


func test_it_is_offered_to_an_armed_piece_only() -> void:
	assert_true(
		CommandContextParser.commands_for(_piece(true)).has(CommandContextParser.HOLD_FIRE_COMMAND),
		"a piece with a weapon can hold its fire"
	)
	assert_false(
		CommandContextParser.commands_for(_piece(false)).has(
			CommandContextParser.HOLD_FIRE_COMMAND
		),
		"a piece with nothing to fire has nothing to hold"
	)


func test_toggling_sets_the_flag_on_armed_pieces_and_skips_the_rest() -> void:
	var armed: Actor = _piece(true)
	var unarmed: Actor = _piece(false)
	OrderDispatcher.toggle_hold_fire([armed, unarmed])
	assert_true(armed.is_holding_fire)
	assert_false(unarmed.is_holding_fire, "a no-op on a piece without a weapon")


func test_toggling_a_partly_held_selection_holds_all_of_it() -> void:
	var first: Actor = _piece()
	var second: Actor = _piece()
	first.is_holding_fire = true
	OrderDispatcher.toggle_hold_fire([first, second])
	assert_true(first.is_holding_fire, "some holding means set, not flip each")
	assert_true(second.is_holding_fire)


func test_toggling_a_wholly_held_selection_releases_all_of_it() -> void:
	var first: Actor = _piece()
	var second: Actor = _piece()
	var unarmed: Actor = _piece(false)
	first.is_holding_fire = true
	second.is_holding_fire = true
	OrderDispatcher.toggle_hold_fire([first, second, unarmed])
	assert_false(first.is_holding_fire)
	assert_false(second.is_holding_fire, "the unarmed piece does not stop 'all' being all")


func test_holding_leaves_the_queue_as_it_was() -> void:
	var piece: Actor = _piece()
	var victim: Actor = _piece()
	piece.update_commands(_attack(victim))
	OrderDispatcher.toggle_hold_fire([piece])
	assert_true(piece.is_holding_fire)
	assert_true(piece.current_command() is Attack, "a pseudo-command touches no queue")


## With the additive modifier the toggle waits its turn: behind what the piece is doing, it
## sets the flag only when its queue reaches it (commitment-and-movement.md §Action timing).
func test_a_queued_hold_fire_waits_behind_the_current_order() -> void:
	var piece: Actor = _piece()
	piece.update_commands(MoveCommand.new(CommandMessage.new(null, null, null, Vector3.ONE)))
	OrderDispatcher.hold_fire([piece], true, null)
	assert_false(piece.is_holding_fire, "not yet: the move comes first")
	var queued: Array = piece.command_receiver.get_command_chain().filter(
		func(c: MoveCommand) -> bool: return c is SetHoldFire
	)
	assert_eq(queued.size(), 1, "it is in the queue")
	queued[0].fulfill_action(piece)
	assert_true(piece.is_holding_fire, "and holds when it is reached")


func test_a_held_piece_acquires_nothing_on_its_own() -> void:
	var piece: Actor = _piece()
	piece.is_holding_fire = true
	assert_null(piece.get_aggro_near_position(), "idle aggro, Defend and Patrol all ask this")


func test_an_attack_releases_the_hold() -> void:
	var piece: Actor = _piece()
	piece.is_holding_fire = true
	piece.update_commands(_attack(_piece()))
	assert_false(piece.is_holding_fire)


func test_a_queued_attack_releases_the_hold_on_receipt() -> void:
	var piece: Actor = _piece()
	piece.is_holding_fire = true
	piece.update_commands(MoveCommand.new(CommandMessage.new(null, null, null, Vector3.ONE)))
	piece.update_commands(_attack(_piece()), true)
	assert_false(piece.is_holding_fire)


func test_an_attack_move_releases_the_hold() -> void:
	var piece: Actor = _piece()
	piece.is_holding_fire = true
	piece.update_commands(AttackMove.new(CommandMessage.new(null, null, null, Vector3.ONE)))
	assert_false(piece.is_holding_fire)


func test_force_fire_and_defend_release_the_hold() -> void:
	for command_type: Script in [FocusFire, Defend]:
		var piece: Actor = _piece()
		piece.is_holding_fire = true
		piece.update_commands(command_type.new(CommandMessage.new(null, null, null, Vector3.ONE)))
		assert_false(piece.is_holding_fire, "%s releases it" % command_type.get_global_name())


func test_a_plain_move_keeps_the_hold() -> void:
	var piece: Actor = _piece()
	piece.is_holding_fire = true
	piece.update_commands(MoveCommand.new(CommandMessage.new(null, null, null, Vector3.ONE)))
	assert_true(piece.is_holding_fire, "only an order to shoot lifts it")


func test_gaining_stealth_holds_fire() -> void:
	var piece: Actor = _piece()
	var stealth := Stealth.new()
	stealth.name = "Stealth"
	piece.add_child(stealth)
	assert_true(piece.is_holding_fire, "a stealthed unit is not given away by idle aggro")


func test_the_button_is_lit_once_every_armed_piece_holds() -> void:
	var first: Actor = _piece()
	var second: Actor = _piece()
	var unarmed: Actor = _piece(false)
	var selection: Array = [first, second, unarmed]
	first.is_holding_fire = true
	assert_false(_state(selection).is_toggled_on, "a partly held selection is not lit")
	second.is_holding_fire = true
	var state: CommandButtonState = _state(selection)
	assert_true(state.is_toggled_on, "the unarmed piece does not count against it")
	assert_eq(
		state.blocker,
		CommandButtonState.Blocker.NONE,
		"lit is not blocked: pressing it again releases the hold"
	)


func _state(a_selection: Array) -> CommandButtonState:
	return CommandButtonState.of(
		CommandContextParser.HOLD_FIRE_COMMAND, a_selection, _commander, false
	)


func test_an_unarmed_piece_holding_fire_shows_no_hold() -> void:
	# Stealth sets the flag on anything it is granted to; only a piece that is offered the
	# button draws the hold, so an unarmed stealthed piece shows no badge or card for it. The
	# hold is drawn for the local player's pieces; that id is a static, so it is read, not assumed.
	_commander.id = RTSController.PLAYER_COMMANDER_ID
	var unarmed := _piece(false)
	unarmed.is_holding_fire = true
	assert_false(ConditionRow._holds_fire(unarmed), "nothing to hold")
	var armed := _piece(true)
	armed.is_holding_fire = true
	assert_true(ConditionRow._holds_fire(armed))
