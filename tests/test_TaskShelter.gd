extends GutTest

## TaskShelter — the Stock Truck's standing order to keep working a Shelter. See
## gdd/systems/commands/unit-tasking.md.
##
## Built from real scenes (truck, Shelter, Compound), like test_WorkDetail.gd: a bare
## off-tree Commandable never gets a real CommandReceiver (its @onready initializer only
## runs on _ready(), which never fires off-tree), and this needs one live to hold and chain
## commands. Every fixture lives under `_world`, added to the actual GUT tree in
## before_each() so _ready() resolves normally.
##
## The cases pinned are the ones the state machine exists for: two trucks contending, a
## claim lapsing, a full truck with no Compound to go to, and the task surviving a pushed
## errand.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_TaskShelter.gd -gexit

const TRUCK: Dictionary = FakePieces.TRUCK
const SHELTER: Dictionary = FakePieces.SHELTER
const COMPOUND: Dictionary = FakePieces.COMPOUND
const TERRESTRIAL: Dictionary = FakePieces.PLAIN

var _world: Node3D
var _commander: Commander


func before_each() -> void:
	_world = Node3D.new()
	_commander = Commander.new()
	_commander.id = 1
	_world.add_child(_commander)
	add_child_autofree(_world)
	_commander.set_physics_process(false)


## A truck owned by `_commander`, positioned at `a_position`, with an ACTIVE TaskShelter
## naming `a_shelter` at sequence `a_sequence` — stamped directly, mirroring what
## RTSController.assign_command_to_units does at issue time.
func _tasked_truck(a_shelter: Entity, a_position: Vector3, a_sequence: int) -> Commandable:
	var truck: Commandable = FakePieces.make(TRUCK)
	_world.add_child(truck)
	truck.set_physics_process(false)
	truck.top_level = true
	truck.commander = _commander
	truck.global_position = a_position
	var task := TaskShelter.new(CommandMessage.new(null, a_shelter))
	task.sequence = a_sequence
	truck.command_receiver.update_commands(task)
	return truck


func _shelter_with_residents(a_count: int) -> Entity:
	var shelter: Entity = FakePieces.make(SHELTER)
	_world.add_child(shelter)
	shelter.set_physics_process(false)
	shelter.top_level = true
	var comp := shelter.get_node("Shelter") as Shelter
	for _i: int in a_count:
		var resident: Commandable = FakePieces.make(TERRESTRIAL)
		_world.add_child(resident)
		resident.top_level = true
		comp.register(resident)
	return shelter


func _compound(a_commander: Commander) -> Commandable:
	var compound: Commandable = FakePieces.make(COMPOUND)
	_world.add_child(compound)
	compound.set_physics_process(false)
	compound.top_level = true
	compound.commander = a_commander
	return compound


func _active_task(a_truck: Commandable) -> TaskShelter:
	return a_truck.current_command() as TaskShelter


#region Holding
func test_holds_when_the_shelter_has_no_residents() -> void:
	var shelter := _shelter_with_residents(0)
	var truck := _tasked_truck(shelter, Vector3.ZERO, 0)
	assert_eq(
		_active_task(truck).get_updated_state(truck), _active_task(truck), "nothing to chase yet"
	)


func test_full_truck_with_no_compound_holds() -> void:
	var shelter := _shelter_with_residents(1)
	var truck := _tasked_truck(shelter, Vector3.ZERO, 0)
	for _i: int in truck.garrison.capacity:
		truck.garrison.garrison(_entity(0))
	assert_eq(
		_active_task(truck).get_updated_state(truck),
		_active_task(truck),
		"full, and nowhere to deposit — hold rather than error"
	)


func test_a_holding_truck_away_from_its_shelter_heads_back() -> void:
	var shelter := _shelter_with_residents(0)
	var truck := _tasked_truck(shelter, Vector3(12.0, 0.0, 12.0), 0)
	assert_true(
		_active_task(truck).should_move(truck),
		"a truck left at the Compound waits at the Shelter, not where the deposit left it"
	)


func test_a_holding_truck_at_its_shelter_stays_put() -> void:
	var shelter := _shelter_with_residents(0)
	var truck := _tasked_truck(shelter, shelter.global_position, 0)
	assert_false(_active_task(truck).should_move(truck))


#endregion


#region Chasing a resident
func test_a_lone_tasked_truck_is_pushed_to_chase_the_resident() -> void:
	var shelter := _shelter_with_residents(1)
	var truck := _tasked_truck(shelter, Vector3.ZERO, 0)
	var errand: Variant = _active_task(truck).get_updated_state(truck)
	assert_true(
		errand is MoveCommand and not (errand is TaskShelter),
		"a plain move — the capture order is the contact, not a special command"
	)
	assert_eq((errand as MoveCommand).message.target, shelter.get_node("Shelter").residents()[0])


func test_only_the_earliest_tasked_truck_chases_the_resident() -> void:
	var shelter := _shelter_with_residents(1)
	var late := _tasked_truck(shelter, Vector3.ZERO, 5)
	var early := _tasked_truck(shelter, Vector3.ZERO, 1)
	assert_true(
		_active_task(early).get_updated_state(early) is MoveCommand,
		"sequence 1 is earliest among the two — it claims the resident"
	)
	assert_eq(
		_active_task(late).get_updated_state(late),
		_active_task(late),
		"sequence 5 waits, by task age, never by distance"
	)


func test_the_claim_lapses_once_the_earliest_truck_fills() -> void:
	var shelter := _shelter_with_residents(1)
	var early := _tasked_truck(shelter, Vector3.ZERO, 1)
	var late := _tasked_truck(shelter, Vector3.ZERO, 5)
	for _i: int in early.garrison.capacity:
		early.garrison.garrison(_entity(0))
	# The earliest truck is now FULL, so it drops out of the resident comparison entirely —
	# the next in line becomes earliest among the LIVE claimants.
	assert_true(
		_active_task(late).get_updated_state(late) is MoveCommand,
		"the earliest claim lapsed (full) — the next truck in line takes it"
	)


#endregion


#region Depositing
func test_a_full_truck_with_a_compound_is_pushed_to_deposit() -> void:
	var shelter := _shelter_with_residents(0)
	var truck := _tasked_truck(shelter, Vector3.ZERO, 0)
	var compound := _compound(_commander)
	for _i: int in truck.garrison.capacity:
		truck.garrison.garrison(_entity(0))
	var errand: Variant = _active_task(truck).get_updated_state(truck)
	assert_true(errand is Interact, "the ordinary DEPOSIT order — it walks and deposits on its own")
	assert_eq((errand as Interact).message.target, compound)


func test_deposits_at_the_nearest_compound_with_room() -> void:
	var shelter := _shelter_with_residents(0)
	var truck := _tasked_truck(shelter, Vector3.ZERO, 0)
	var far := _compound(_commander)
	far.global_position = Vector3(100, 0, 0)
	var near := _compound(_commander)
	near.global_position = Vector3(5, 0, 0)
	for _i: int in truck.garrison.capacity:
		truck.garrison.garrison(_entity(0))
	var errand: Interact = _active_task(truck).get_updated_state(truck) as Interact
	assert_eq(errand.message.target, near)


func test_a_full_compound_is_not_offered_as_a_deposit_target() -> void:
	var shelter := _shelter_with_residents(0)
	var truck := _tasked_truck(shelter, Vector3.ZERO, 0)
	var full_compound := _compound(_commander)
	full_compound.global_position = Vector3(5, 0, 0)
	for _i: int in full_compound.garrison.capacity:
		full_compound.garrison.garrison(_entity(0))
	var open_compound := _compound(_commander)
	open_compound.global_position = Vector3(100, 0, 0)
	for _i: int in truck.garrison.capacity:
		truck.garrison.garrison(_entity(0))
	var errand: Interact = _active_task(truck).get_updated_state(truck) as Interact
	assert_eq(errand.message.target, open_compound, "the nearer one is full — go past it")


#endregion


#region The task survives a pushed errand
func test_the_task_resumes_behind_the_errand_it_pushed() -> void:
	var shelter := _shelter_with_residents(1)
	var truck := _tasked_truck(shelter, Vector3.ZERO, 0)
	var task := _active_task(truck)
	truck.command_receiver._process_commands()
	assert_true(
		truck.current_command() is MoveCommand and not (truck.current_command() is TaskShelter),
		"the errand is now active"
	)
	assert_eq(
		truck.get_command_chain(),
		[truck.current_command(), task] as Array[MoveCommand],
		"and the task itself is queued right behind it, to resume once the errand ends"
	)


func test_a_direct_player_order_clears_the_task_entirely() -> void:
	var shelter := _shelter_with_residents(1)
	var truck := _tasked_truck(shelter, Vector3.ZERO, 0)
	truck.command_receiver._process_commands()  # push the chase errand; task now queued behind it
	assert_true(truck.has_command())
	truck.update_commands(MoveCommand.new(CommandMessage.new(null, null)))
	assert_eq(
		truck.get_command_chain().size(), 1, "one order — the new one, nothing queued behind it"
	)
	assert_false(
		truck.get_command_chain().any(func(c: MoveCommand) -> bool: return c is TaskShelter),
		"the task is gone, not merely displaced"
	)


#endregion


#region Precondition
func test_meets_precondition_for_a_garrisoned_actor_and_a_shelter_target() -> void:
	var shelter := _shelter_with_residents(0)
	var truck: Commandable = FakePieces.make(TRUCK)
	_world.add_child(truck)
	assert_eq(
		TaskShelter.meets_precondition(truck, CommandMessage.new(null, shelter)),
		MoveCommand.PreconditionFailureCause.NONE
	)


func test_meets_precondition_refuses_a_non_shelter_target() -> void:
	var truck: Commandable = FakePieces.make(TRUCK)
	_world.add_child(truck)
	var other: Commandable = FakePieces.make(TRUCK)
	_world.add_child(other)
	assert_ne(
		TaskShelter.meets_precondition(truck, CommandMessage.new(null, other)),
		MoveCommand.PreconditionFailureCause.NONE
	)


func test_meets_precondition_refuses_an_actor_with_no_garrison() -> void:
	var shelter := _shelter_with_residents(0)
	var soldier: Commandable = FakePieces.make(TERRESTRIAL)
	_world.add_child(soldier)
	assert_ne(
		TaskShelter.meets_precondition(soldier, CommandMessage.new(null, shelter)),
		MoveCommand.PreconditionFailureCause.NONE
	)


#endregion


## A bare neutral Commandable, for filling a cage without caring who it is.
func _entity(a_commander_id: int) -> Commandable:
	var e := FakePieces.make(TERRESTRIAL) as Commandable
	_world.add_child(e)
	e.top_level = true
	e.commander = _commanded(a_commander_id)
	return e


func _commanded(a_id: int) -> Commander:
	if a_id == _commander.id:
		return _commander
	var c := Commander.new()
	c.id = a_id
	_world.add_child(c)
	return c
