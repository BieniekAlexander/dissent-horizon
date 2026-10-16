extends GutTest

## SimulationStepper: every entity in a scenario steps in spawn-serial order, whatever order the
## scene tree holds it in; a tick steps what was in play when it started; and the tick's deaths
## resolve after every entity has stepped. gdd/systems/commands/the-simulation-step.md.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_SimulationStepper.gd -gexit

const DELTA: float = 1.0 / 30.0


## A component that writes its entity's serial into a shared log each time it is stepped, and
## runs an optional action after.
class Recorder:
	extends Node
	var log: Array[int] = []
	var action: Callable = Callable()

	func simulation_step(_a_delta: float) -> void:
		log.append((get_parent() as Entity).spawn_serial)
		if action.is_valid():
			action.call()


var _stepper: SimulationStepper = null


func after_each() -> void:
	SpatialIndex.is_verifying = false


var _log: Array[int] = []


func before_each() -> void:
	# Every tick of these tests also checks the index's dirty marks against a fresh scan.
	SpatialIndex.is_verifying = true
	_stepper = SimulationStepper.new()
	add_child_autofree(_stepper)
	_stepper.set_physics_process(false)
	_log = []


## A unit numbered `a_serial` and handed to the stepper, as Scenario.register_entity does, with
## a Recorder that writes to the shared log.
func _enlisted(a_serial: int) -> Actor:
	var unit: Actor = FakePieces.unit()
	add_child_autofree(unit)
	unit.set_physics_process(false)
	unit.spawn_serial = a_serial
	_stepper.enlist(unit)
	var recorder := Recorder.new()
	recorder.name = "Recorder"
	recorder.log = _log
	unit.add_child(recorder)
	return unit


func _recorder(a_unit: Actor) -> Recorder:
	return a_unit.get_node("Recorder") as Recorder


func test_entities_step_in_serial_order_not_tree_order() -> void:
	var first := _enlisted(1)
	var second := _enlisted(2)
	var third := _enlisted(3)
	# Tree order is now 3, 1, 2; serial order is unchanged.
	move_child(third, 0)
	_stepper.step(DELTA)
	assert_eq(_log, [1, 2, 3])
	assert_true(first.is_inside_tree() and second.is_inside_tree())


func test_an_entity_enlisted_mid_tick_first_steps_on_the_next() -> void:
	var spawner := _enlisted(1)
	var spawned: Array[Actor] = []
	_recorder(spawner).action = func() -> void:
		if spawned.is_empty():
			spawned.append(_enlisted(2))
	_stepper.step(DELTA)
	assert_eq(_log, [1], "the spawn waits for the next tick")
	_stepper.step(DELTA)
	assert_eq(_log, [1, 1, 2])


func test_a_node_added_mid_tick_first_steps_on_the_next() -> void:
	var host := _enlisted(1)
	var other := _enlisted(2)
	var late := Recorder.new()
	late.log = _log
	_recorder(host).action = func() -> void:
		if late.get_parent() == null:
			other.add_child(late)
	_stepper.step(DELTA)
	assert_eq(_log, [1, 2], "the added node waits for the next tick")
	_stepper.step(DELTA)
	assert_eq(_log, [1, 2, 1, 2, 2])


func test_an_entity_out_of_the_tree_is_skipped_and_resumes_on_return() -> void:
	var first := _enlisted(1)
	var second := _enlisted(2)
	remove_child(first)
	_stepper.step(DELTA)
	assert_eq(_log, [2])
	add_child(first)
	_stepper.step(DELTA)
	assert_eq(_log, [2, 1, 2], "it keeps its place in serial order")
	assert_true(second.is_inside_tree())


func test_a_freed_entity_drops_out() -> void:
	var first := _enlisted(1)
	_enlisted(2)
	first.free()
	_stepper.step(DELTA)
	assert_eq(_log, [2])


func test_a_piece_killed_by_an_earlier_serial_does_not_act_and_dies_that_tick() -> void:
	var killer := _enlisted(1)
	var victim := _enlisted(2)
	_recorder(killer).action = func() -> void: victim.defense.hp = 0.0
	_stepper.step(DELTA)
	assert_true(victim.is_queued_for_deletion(), "the death resolves on the tick that dealt it")


func test_a_piece_killed_by_a_later_serial_dies_the_same_tick() -> void:
	var victim := _enlisted(1)
	var killer := _enlisted(2)
	_recorder(killer).action = func() -> void: victim.defense.hp = 0.0
	_stepper.step(DELTA)
	assert_true(victim.is_queued_for_deletion(), "not a tick later, as tree order once made it")


func test_a_dying_piece_does_not_take_its_own_tick() -> void:
	var victim := _enlisted(1)
	victim.defense.hp = 0.0
	# Actor.simulation_step's first act on a live piece is to count down its stagger.
	victim._stagger_ticks = 5
	_stepper.step(DELTA)
	assert_eq(victim._stagger_ticks, 5, "a piece at zero HP skips its own step")
	assert_true(victim.is_queued_for_deletion())


## The scripts under scripts/entities/ allowed a `_physics_process`: Entity's own fallback (it
## steps itself outside a scenario), and presentation that never changes the simulation.
const PHYSICS_PROCESS_ALLOWED: Array[String] = [
	"res://scripts/entities/entity.gd",
	"res://scripts/entities/animation/animation_rig.gd",
]


## A piece's per-tick simulation work runs through the stepper, in serial order. A component
## that ticks in `_physics_process` instead runs in tree order, outside it, and nothing else
## would say so.
func test_no_entity_script_ticks_outside_the_stepper() -> void:
	var offenders: Array[String] = []
	for path: String in _scripts_under("res://scripts/entities"):
		if path in PHYSICS_PROCESS_ALLOWED:
			continue
		if FileAccess.get_file_as_string(path).contains("func _physics_process("):
			offenders.append(path)
	assert_eq(offenders, [] as Array[String], "define simulation_step instead")


func _scripts_under(a_root: String) -> Array[String]:
	var out: Array[String] = []
	for entry: String in DirAccess.get_directories_at(a_root):
		out.append_array(_scripts_under(a_root.path_join(entry)))
	for entry: String in DirAccess.get_files_at(a_root):
		if entry.ends_with(".gd"):
			out.append(a_root.path_join(entry))
	return out


# --- The decide phase --------------------------------------------------------------------

const OWN: int = 1
const FOE: int = 2


func _commander(a_id: int) -> Commander:
	var commander := Commander.new()
	commander.id = a_id
	add_child_autofree(commander)
	return commander


## A piece built from `a_options`, owned by `a_commander` at `a_at`, numbered `a_serial` and
## handed to the stepper.
func _enlisted_piece(
	a_options: Dictionary, a_commander: Commander, a_at: Vector3, a_serial: int
) -> Actor:
	var piece := FakePieces.make(a_options) as Actor
	add_child_autofree(piece)
	piece.set_physics_process(false)
	piece.ownership.commander = a_commander
	piece.global_position = a_at
	piece.spawn_serial = a_serial
	_stepper.enlist(piece)
	return piece


func test_an_idle_piece_attacks_what_it_decided_on_the_same_tick() -> void:
	Fog._fogs_by_commander.clear()
	var enemy := _enlisted_piece(FakePieces.BUILDER, _commander(FOE), Vector3(3, 0, 0), 1)
	var shooter := _enlisted_piece(FakePieces.SOLDIER, _commander(OWN), Vector3.ZERO, 2)
	await wait_physics_frames(2)
	_stepper.step(DELTA)
	assert_true(shooter.current_command() is Attack, "it picked a target and started on it")
	assert_same(shooter.current_command().message.target, enemy)


## Every piece decides before any acts, so a target an earlier piece kills in the act phase
## was still standing when the shooter decided — and the act phase drops the decision.
func test_a_decided_target_killed_before_the_act_is_dropped() -> void:
	Fog._fogs_by_commander.clear()
	var killer := _enlisted(1)
	var enemy := _enlisted_piece(FakePieces.BUILDER, _commander(FOE), Vector3(3, 0, 0), 2)
	var shooter := _enlisted_piece(FakePieces.SOLDIER, _commander(OWN), Vector3.ZERO, 3)
	_recorder(killer).action = func() -> void: enemy.defense.hp = 0.0
	await wait_physics_frames(2)
	_stepper.step(DELTA)
	assert_null(shooter.current_command(), "no attack on a target already dead")
	assert_true(enemy.is_queued_for_deletion())


## An attack-move's scan for something to fight is decided too: the swap to an Attack happens
## the same tick when the target holds, and not at all when an earlier piece killed it first.
func test_an_attack_move_swaps_to_what_it_decided_on() -> void:
	Fog._fogs_by_commander.clear()
	var enemy := _enlisted_piece(FakePieces.BUILDER, _commander(FOE), Vector3(3, 0, 0), 1)
	var shooter := _enlisted_piece(FakePieces.SOLDIER, _commander(OWN), Vector3.ZERO, 2)
	shooter.update_commands(AttackMove.new(CommandMessage.new(null, null, null, Vector3(0, 0, 3))))
	await wait_physics_frames(2)
	_stepper.step(DELTA)
	assert_true(shooter.current_command() is Attack)
	assert_same(shooter.current_command().message.target, enemy)


func test_an_attack_move_drops_a_decided_target_killed_before_it_acts() -> void:
	Fog._fogs_by_commander.clear()
	var killer := _enlisted(1)
	var enemy := _enlisted_piece(FakePieces.BUILDER, _commander(FOE), Vector3(3, 0, 0), 2)
	var shooter := _enlisted_piece(FakePieces.SOLDIER, _commander(OWN), Vector3.ZERO, 3)
	shooter.update_commands(AttackMove.new(CommandMessage.new(null, null, null, Vector3(0, 0, 3))))
	_recorder(killer).action = func() -> void: enemy.defense.hp = 0.0
	await wait_physics_frames(2)
	_stepper.step(DELTA)
	assert_true(shooter.current_command() is AttackMove, "it carries on with the move")


## A decision counts only in the round that made it: one left over is never read a tick late.
func test_a_decision_is_never_read_on_a_later_tick() -> void:
	Fog._fogs_by_commander.clear()
	_enlisted_piece(FakePieces.BUILDER, _commander(FOE), Vector3(3, 0, 0), 1)
	var shooter := _enlisted_piece(FakePieces.SOLDIER, _commander(OWN), Vector3.ZERO, 2)
	await wait_physics_frames(2)
	SimulationStepper.begin_round()
	shooter.simulation_decide()
	SimulationStepper.begin_round()
	assert_null(shooter.take_decided_aggro(), "last tick's pick is not this tick's")


## A defender's scan around its post is decided too, and leashed to the area it guards.
func test_a_defender_engages_what_it_decided_on_and_leashes_it() -> void:
	Fog._fogs_by_commander.clear()
	var enemy := _enlisted_piece(FakePieces.BUILDER, _commander(FOE), Vector3(3, 0, 0), 1)
	var guard := _enlisted_piece(FakePieces.SOLDIER, _commander(OWN), Vector3.ZERO, 2)
	guard.update_commands(Defend.new(CommandMessage.new(null, null, null, Vector3.ZERO)))
	await wait_physics_frames(2)
	_stepper.step(DELTA)
	assert_true(guard.current_command() is Attack)
	assert_same(guard.current_command().message.target, enemy)
	assert_not_null(guard.current_command().message.aggro_shape, "leashed to the defended area")


func test_a_defender_drops_a_decided_target_killed_before_it_acts() -> void:
	Fog._fogs_by_commander.clear()
	var killer := _enlisted(1)
	var enemy := _enlisted_piece(FakePieces.BUILDER, _commander(FOE), Vector3(3, 0, 0), 2)
	var guard := _enlisted_piece(FakePieces.SOLDIER, _commander(OWN), Vector3.ZERO, 3)
	guard.update_commands(Defend.new(CommandMessage.new(null, null, null, Vector3.ZERO)))
	_recorder(killer).action = func() -> void: enemy.defense.hp = 0.0
	await wait_physics_frames(2)
	_stepper.step(DELTA)
	assert_true(guard.current_command() is Defend, "it stays on guard")


# --- Sleepy updates ----------------------------------------------------------------------


## A component that promises `promise` ticks of sleep after every step and counts the ticks
## it lives through — stepped, or handed back by catch_up on waking.
class Sleeper:
	extends Node
	var promise: int = 0
	var stepped: int = 0
	var counted: int = 0

	func simulation_step(_a_delta: float) -> void:
		stepped += 1
		counted += 1

	func sleep_ticks() -> int:
		return promise

	func catch_up(a_ticks: int) -> void:
		counted += a_ticks


## A bare entity, numbered `a_serial` and enlisted, stepping one Sleeper promising `a_promise`.
func _sleepy(a_serial: int, a_promise: int) -> Sleeper:
	var entity: Entity = FakePieces.feature()
	add_child_autofree(entity)
	entity.set_physics_process(false)
	entity.spawn_serial = a_serial
	_stepper.enlist(entity)
	var sleeper := Sleeper.new()
	sleeper.promise = a_promise
	entity.add_child(sleeper)
	return sleeper


func _steps(a_count: int) -> void:
	for _i: int in a_count:
		_stepper.step(DELTA)


func test_a_promised_sleep_skips_ticks_and_counts_them_back_on_waking() -> void:
	var sleeper := _sleepy(1, 4)
	_steps(6)
	assert_eq(sleeper.stepped, 2, "it steps, sleeps four ticks, steps again")
	assert_eq(sleeper.counted, 6, "and the slept ticks are counted as if stepped")


func test_a_wake_steps_the_entity_on_the_next_tick() -> void:
	var sleeper := _sleepy(1, 100)
	_steps(1)
	sleeper.get_parent().call(&"wake")
	_steps(1)
	assert_eq(sleeper.stepped, 2)
	assert_eq(sleeper.counted, 2)


func test_one_node_that_cannot_promise_keeps_the_entity_awake() -> void:
	var sleeper := _sleepy(1, 100)
	var other := Recorder.new()
	other.log = _log
	sleeper.get_parent().add_child(other)
	_steps(3)
	assert_eq(sleeper.stepped, 3)


func test_with_sleep_off_every_entity_steps_every_tick() -> void:
	var sleeper := _sleepy(1, 100)
	SimulationStepper.is_sleep_enabled = false
	_steps(3)
	SimulationStepper.is_sleep_enabled = true
	assert_eq(sleeper.stepped, 3)


## A node added to a sleeping entity wakes it: the newcomer may have work of its own.
func test_a_node_added_to_a_sleeper_wakes_it() -> void:
	var sleeper := _sleepy(1, 100)
	_steps(1)
	var late := Sleeper.new()
	late.promise = 100
	sleeper.get_parent().add_child(late)
	_steps(1)
	assert_eq(sleeper.stepped, 2)
	assert_eq(late.stepped, 1)


## An immobile armed piece, idle, sleeps while no hostile is near — and the tick one comes
## within its aggro range, it wakes before anything decides and starts on it, as awake.
func test_an_idle_armed_piece_sleeps_until_an_enemy_comes_near() -> void:
	Fog._fogs_by_commander.clear()
	var turret := _enlisted_piece({"weapon": {"ground": 6.0}}, _commander(OWN), Vector3.ZERO, 1)
	_steps(3)
	assert_true(turret.is_asleep_at(_stepper._tick + 1), "nothing near: it sleeps")
	var enemy := _enlisted_piece(FakePieces.BUILDER, _commander(FOE), Vector3(3, 0, 0), 2)
	await wait_physics_frames(2)
	_steps(1)
	assert_true(turret.current_command() is Attack, "woken by the index, it attacks at once")
	assert_same(turret.current_command().message.target, enemy)


## Catching a weapon up over slept ticks lands it exactly where stepping them would have.
func test_a_weapon_caught_up_matches_one_stepped() -> void:
	var stepped := _enlisted_piece({"weapon": {"ground": 6.0}}, _commander(OWN), Vector3.ZERO, 1)
	var slept := _enlisted_piece({"weapon": {"ground": 6.0}}, _commander(OWN), Vector3(9, 0, 0), 2)
	var a: Weapon = stepped.weapon_inventory.get_child(0)
	var b: Weapon = slept.weapon_inventory.get_child(0)
	for weapon: Weapon in [a, b]:
		weapon._ammo = 0
		weapon._reload_timer_ticks = 5
		weapon._split_timer_ticks = 3
	for _i: int in 8:
		a.simulation_step(DELTA)
	b.catch_up(8)
	assert_eq(
		[b._ammo, b._reload_timer_ticks, b._split_timer_ticks],
		[a._ammo, a._reload_timer_ticks, a._split_timer_ticks]
	)
