extends GutTest

## Embark — the HOST side of a garrison order. The player selects something that holds
## units, right-clicks a friendly one, and the order goes out in two halves: an Occupy to
## the unit being called, and a follow to the host so the two meet in the middle.
##
## What is checked here is the RULE, not the walk: which hosts may be given the order,
## which one of several collects it, and that the masks question is asked in exactly one
## place (Occupy.host_admits) so the two directions of the mechanic cannot disagree.
##
## Scenes are load()ed INSIDE the tests rather than preloaded at file scope — a file-scope
## preload of an entity scene runs at parse time and can fire Tool's static registry build
## before the registry exists, poisoning every test after it. See CLAUDE.md §Running and
## testing.

const TRANSPORT_PATH := "res://scenes/entities/units/an/an_mechStrong_transport.tscn"
const SOLDIER_PATH := "res://scenes/entities/units/cl/cl_bioLight_antiLight.tscn"
const OPEN_GARRISON_PATH := "res://scenes/entities/structures/nt/nt_building_square.tscn"

func _commanded(a_id: int) -> Commander:
	var c := Commander.new()
	c.id = a_id
	add_child_autofree(c)
	return c

func _entity(a_path: String, a_commander_id: int) -> Commandable:
	var e := (load(a_path) as PackedScene).instantiate() as Commandable
	add_child_autofree(e)
	e.ownership.commander = _commanded(a_commander_id)
	return e

func _message_for(a_target: Entity) -> CommandMessage:
	return CommandMessage.new(null, a_target)

func _passes(a_host: Commandable, a_occupant: Commandable) -> bool:
	return Embark.meets_precondition(a_host, _message_for(a_occupant)) \
		== MoveCommand.PreconditionFailureCause.NONE

#region Who may be told to collect whom
func test_a_transport_may_be_told_to_collect_a_friendly_soldier() -> void:
	assert_true(_passes(_entity(TRANSPORT_PATH, 1), _entity(SOLDIER_PATH, 1)))

func test_an_immobile_host_may_still_collect() -> void:
	# The whole of a bunker's half of the order is the Occupy it hands out; it has nowhere
	# to walk and that is not a reason to refuse.
	assert_true(_passes(_entity(OPEN_GARRISON_PATH, 1), _entity(SOLDIER_PATH, 1)))

func test_a_host_with_no_garrison_cannot_collect() -> void:
	assert_false(_passes(_entity(SOLDIER_PATH, 1), _entity(SOLDIER_PATH, 1)))

func test_an_enemy_unit_is_not_collected() -> void:
	assert_false(_passes(_entity(TRANSPORT_PATH, 1), _entity(SOLDIER_PATH, 2)))

func test_a_host_cannot_collect_itself() -> void:
	var transport: Commandable = _entity(TRANSPORT_PATH, 1)
	assert_false(_passes(transport, transport))

func test_a_unit_the_masks_reject_is_not_collected() -> void:
	var transport: Commandable = _entity(TRANSPORT_PATH, 1)
	var soldier: Commandable = _entity(SOLDIER_PATH, 1)
	assert_true(_passes(transport, soldier), "admitted before the mask is narrowed")
	transport.garrison.occupiable_frames = 0
	assert_false(_passes(transport, soldier), "a closed hold takes nobody by order")

## The one thing Embark asks that Occupy deliberately does not. A unit ORDERED into a full
## garrison walks over and waits for a slot; a player HOVERING a unit over a full transport
## is asking whether calling it in would achieve anything, and it would not.
func test_a_full_host_is_not_offered_the_order() -> void:
	var transport: Commandable = _entity(TRANSPORT_PATH, 1)
	var soldier: Commandable = _entity(SOLDIER_PATH, 1)
	transport.garrison.capacity = 0
	assert_false(_passes(transport, soldier))
	assert_true(Occupy.host_admits(soldier, transport),
		"Occupy still allows it — capacity is checked on arrival there")
#endregion

#region Occupy asks the same question from the other end
func test_the_masks_rule_is_stated_once() -> void:
	var transport: Commandable = _entity(TRANSPORT_PATH, 1)
	var soldier: Commandable = _entity(SOLDIER_PATH, 1)
	assert_eq(
		Occupy.meets_precondition(soldier, _message_for(transport)),
		MoveCommand.PreconditionFailureCause.NONE,
		"the soldier may walk in of its own accord")
	assert_true(_passes(transport, soldier), "and may be called in")
	transport.garrison.occupiable_armours = 0
	assert_ne(Occupy.meets_precondition(soldier, _message_for(transport)),
		MoveCommand.PreconditionFailureCause.NONE)
	assert_false(_passes(transport, soldier), "both directions close together")
#endregion

#region Which host collects
func test_the_nearest_applicable_host_takes_the_order() -> void:
	var near: Commandable = _entity(TRANSPORT_PATH, 1)
	var far: Commandable = _entity(TRANSPORT_PATH, 1)
	var soldier: Commandable = _entity(SOLDIER_PATH, 1)
	soldier.global_position = Vector3(10.0, 0.0, 0.0)
	near.global_position = Vector3(8.0, 0.0, 0.0)
	far.global_position = Vector3(-30.0, 0.0, 0.0)
	assert_eq(Embark.nearest_host([far, near], _message_for(soldier)), [near])
	assert_eq(Embark.nearest_host([near, far], _message_for(soldier)), [near],
		"and the answer does not depend on selection order")

func test_no_hosts_means_nobody_collects() -> void:
	assert_eq(Embark.nearest_host([], _message_for(_entity(SOLDIER_PATH, 1))), [])
#endregion

#region What the order actually does
## The whole of the host's effect on the world: it hands the unit an Occupy aimed back at
## itself. Occupy is still the only thing that puts a unit inside a garrison.
func test_the_first_tick_hands_the_passenger_an_occupy() -> void:
	var transport: Commandable = _entity(TRANSPORT_PATH, 1)
	var soldier: Commandable = _entity(SOLDIER_PATH, 1)
	var command := Embark.new(_message_for(soldier))
	assert_eq(command.get_updated_state(transport), command, "and the order carries on")
	var handed: MoveCommand = soldier.current_command()
	assert_true(handed is Occupy, "the passenger was ordered aboard")
	assert_eq(handed.message.target, transport, "aimed back at the host that called it")

## Handed out ONCE. A player who re-orders the passenger elsewhere is not overruled every
## tick by a host that is still following it.
func test_the_passenger_is_not_re_ordered_every_tick() -> void:
	var transport: Commandable = _entity(TRANSPORT_PATH, 1)
	var soldier: Commandable = _entity(SOLDIER_PATH, 1)
	var command := Embark.new(_message_for(soldier))
	command.get_updated_state(transport)
	soldier.update_commands(Stop.new(_message_for(null)))
	command.get_updated_state(transport)
	assert_true(soldier.current_command() is Stop, "the player's later order stands")

## A garrisoned unit is ORPHANED, not freed, so is_instance_valid still reports true for it —
## tree membership is what says the order is over.
func test_the_order_ends_once_the_passenger_is_aboard() -> void:
	var transport: Commandable = _entity(TRANSPORT_PATH, 1)
	var soldier: Commandable = _entity(SOLDIER_PATH, 1)
	var command := Embark.new(_message_for(soldier))
	command.get_updated_state(transport)
	transport.garrison.garrison(soldier)
	assert_true(is_instance_valid(soldier), "still alive, just out of the world")
	assert_null(command.get_updated_state(transport))

## An immobile host is still worth giving the order to — its whole half of it is the Occupy
## it handed out — but it has nowhere to walk.
func test_an_immobile_host_hands_the_order_out_and_stays_put() -> void:
	var bunker: Commandable = _entity(OPEN_GARRISON_PATH, 1)
	var soldier: Commandable = _entity(SOLDIER_PATH, 1)
	var command := Embark.new(_message_for(soldier))
	command.get_updated_state(bunker)
	assert_true(soldier.current_command() is Occupy)
	assert_false(command.should_move(bunker))

func test_a_mobile_host_walks_to_meet_the_passenger() -> void:
	var transport: Commandable = _entity(TRANSPORT_PATH, 1)
	assert_true(Embark.new(_message_for(_entity(SOLDIER_PATH, 1))).should_move(transport))

## Meeting the passenger is not the end of the order — boarding is.
func test_arriving_does_not_end_the_order() -> void:
	assert_false(Embark.new(_message_for(_entity(SOLDIER_PATH, 1))).ends_on_arrival())
#endregion

#region The rest of the selection
## Right-clicking a friendly unit with a transport and four soldiers selected means
## "everyone go there, and you pick him up" — the soldiers are not skipped the way an
## actor incapable of a command normally is.
func test_embark_asks_for_bystander_moves() -> void:
	assert_true(Embark.bystanders_move())

func test_nothing_else_does() -> void:
	for command_type: Script in [MoveCommand, Attack, AttackMove, Occupy, Build, Stop,
			Defend, Evacuate, FocusFire]:
		assert_false(command_type.bystanders_move(),
			"%s keeps the standing mixed-selection rule" % command_type)
#endregion

#region Capability
func test_a_garrison_owner_advertises_the_command() -> void:
	var commands: Array = CommandContextParser.commands_for(_entity(TRANSPORT_PATH, 1))
	assert_true(commands.has("command_embark"))

func test_a_plain_soldier_does_not() -> void:
	assert_false(CommandContextParser.commands_for(_entity(SOLDIER_PATH, 1)).has("command_embark"))

## A live Embark has to be recognisable as one, or a unit transformation would judge a
## queued Embark unportable and truncate everything behind it.
func test_a_live_embark_names_itself() -> void:
	var command := Embark.new(_message_for(_entity(SOLDIER_PATH, 1)))
	assert_eq(CommandContextParser.name_for(command), "command_embark")
#endregion
