extends GutTest

## An emission running its phase list: a list of any length runs in order, a moving phase can
## fly through its destination and pay out along the way, a phase runs scenario events on its
## own cadence, and the swept impact test ends a flight at what it struck. Each case builds its
## emission in code — the shipped roster's behaviour is tools/emission_trace.tscn's to watch.
## See gdd/systems/combat/projectiles.md §Phases.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gtest=res://tests/test_EmissionPhaseRuntime.gd -gdir=res://tests/none -gexit

## Well past the longest emission built here.
const MAX_TICKS: int = 120
const LAUNCH: Vector3 = Vector3.ZERO
const AIM: Vector3 = Vector3(6.0, 0.0, 0.0)
const WALL_X: float = 3.0


## Hands its events a stand-in manager; its RecordingPayload keeps the record.
class RecordingEmission:
	extends Entity
	var manager: ScenarioTriggerManager

	func _resolve_trigger_manager() -> ScenarioTriggerManager:
		return manager


## Records each payload application — the tick, where the emission was, whom it was aimed at —
## instead of applying one.
class RecordingPayload:
	extends Payload
	var hits: Array[Dictionary] = []

	func apply() -> void:
		var aimed_at: Variant = target
		hits.append(
			{
				"frame": Engine.get_physics_frames(),
				"position": host().global_position,
				"target": target,
				"phase": _phased().phase_index(),
				"miss":
				(
					host().global_position.distance_to((aimed_at as Node3D).global_position)
					if aimed_at is Node3D and is_instance_valid(aimed_at)
					else -1.0
				)
			}
		)


## Records where it ran, into an array the test holds — the event is freed with its emission.
class RecordingEvent:
	extends AbstractEvent
	var runs: Array[Vector3]

	func execute(_a_manager: ScenarioTriggerManager) -> void:
		runs.append(global_position)


func _phase(a_values: Dictionary) -> EmissionPhase:
	var phase: EmissionPhase = EmissionPhase.new()
	for key: String in a_values:
		phase.set(key, a_values[key])
	return phase


func _emission(a_phases: Array[EmissionPhase]) -> RecordingEmission:
	var emission: RecordingEmission = RecordingEmission.new()
	var payload: RecordingPayload = RecordingPayload.new()
	payload.name = "Payload"
	payload.hitscan = true
	emission.add_child(payload)
	var ownership: Ownership = Ownership.new()
	ownership.name = "Ownership"
	emission.add_child(ownership)
	var locomotion: PhasedLocomotion = PhasedLocomotion.new()
	locomotion.name = "Locomotion"
	emission.add_child(locomotion)
	for phase: EmissionPhase in a_phases:
		emission.add_child(phase)
	emission.manager = ScenarioTriggerManager.new()
	autofree(emission.manager)
	return emission


func _payload(a_emission: RecordingEmission) -> RecordingPayload:
	return a_emission.get_node("Payload") as RecordingPayload


## Launches `a_emission` from LAUNCH at `a_target`, runs it to expiry, and returns how many
## ticks it lived. The record survives on the returned dictionary; the emission frees itself.
func _run(a_emission: RecordingEmission, a_target: Variant = AIM) -> Dictionary:
	add_child(a_emission)
	a_emission.global_position = LAUNCH
	Emitter.launch(a_emission, null, a_target)
	var record: Dictionary = {"hits": _payload(a_emission).hits, "ticks": 0}
	while is_instance_valid(a_emission) and record["ticks"] < MAX_TICKS:
		await get_tree().physics_frame
		record["ticks"] += 1
	if is_instance_valid(a_emission):
		a_emission.queue_free()
	return record


func test_phases_run_in_order_however_many_there_are() -> void:
	var emission: RecordingEmission = _emission(
		[
			_phase({"speed": 30.0}),
			_phase({"ends_on_arrival": false, "lifespan_seconds": 0.0, "applies_payload": true}),
			_phase({"ends_on_arrival": false, "lifespan_seconds": 0.2}),
			_phase({"ends_on_arrival": false, "lifespan_seconds": 0.0, "applies_payload": true}),
		]
	)
	var record: Dictionary = await _run(emission)
	var phases_hit: Array = record["hits"].map(func(h: Dictionary) -> int: return h["phase"])
	assert_eq(phases_hit, [1, 3], "each payload phase pays out once, in order")
	assert_gt(
		record["hits"][1]["frame"] - record["hits"][0]["frame"],
		TimeUtils.ticks_from_seconds(0.2) - 1,
		"the phase between them lasted its lifespan"
	)


func test_a_sonic_sweep_flies_through_and_pays_out_all_the_way() -> void:
	# One phase, no impact: it passes its destination, pays out every tick, and expires.
	var emission: RecordingEmission = _emission(
		[
			_phase(
				{
					"speed": 30.0,
					"ends_on_arrival": false,
					"lifespan_seconds": 0.5,
					"applies_payload": true,
					"payload_period_seconds": 0.0
				}
			),
		]
	)
	var record: Dictionary = await _run(emission)
	var hits: Array = record["hits"]
	assert_eq(hits.size(), TimeUtils.ticks_from_seconds(0.5), "every tick of its lifespan")
	assert_gt(hits[-1]["position"].x, AIM.x, "carried on past its destination")
	assert_gt(hits[-1]["position"].x, hits[0]["position"].x, "paid out along the way")


func test_a_trail_runs_its_events_on_cadence_where_the_emission_is() -> void:
	var trail: EmissionPhase = _phase(
		{
			"speed": 15.0,
			"ends_on_arrival": false,
			"lifespan_seconds": 0.5,
			"event_period_seconds": 0.1
		}
	)
	var runs: Array[Vector3] = []
	var event: RecordingEvent = RecordingEvent.new()
	event.runs = runs
	trail.add_child(event)
	await _run(_emission([trail]))
	var expected: int = ceili(
		float(TimeUtils.ticks_from_seconds(0.5)) / TimeUtils.ticks_from_seconds(0.1)
	)
	assert_eq(runs.size(), expected, "once per period, from the first tick")
	assert_gt(runs[-1].x, runs[0].x, "each drop where the emission had got to")


func test_a_swept_shot_lands_on_what_it_struck() -> void:
	var wall: Entity = _wall(CollisionLayers.Mask.STRUCTURE_BLOCKER)
	await get_tree().physics_frame
	var emission: RecordingEmission = _emission(
		[
			_phase({"speed": 30.0, "impact_mask": CollisionLayers.Mask.STRUCTURE_BLOCKER}),
			_phase({"ends_on_arrival": false, "lifespan_seconds": 0.0, "applies_payload": true}),
		]
	)
	var record: Dictionary = await _run(emission)
	assert_eq(record["hits"].size(), 1)
	assert_eq(record["hits"][0]["target"], wall, "the structure took it as the target")
	assert_almost_eq(record["hits"][0]["position"].x, WALL_X - 0.5, 0.05, "at the contact")


func test_a_swept_shot_into_terrain_is_absorbed() -> void:
	var ground: StaticBody3D = StaticBody3D.new()
	ground.collision_layer = CollisionLayers.Mask.TERRAIN
	ground.add_child(_box_shape())
	add_child_autofree(ground)
	ground.global_position = Vector3(WALL_X, 0.0, 0.0)
	var behind: Entity = _wall(0)
	behind.global_position = AIM
	await get_tree().physics_frame
	var emission: RecordingEmission = _emission(
		[
			_phase({"speed": 30.0, "impact_mask": CollisionLayers.Mask.TERRAIN}),
			_phase({"ends_on_arrival": false, "lifespan_seconds": 0.0, "applies_payload": true}),
		]
	)
	var record: Dictionary = await _run(emission, behind)
	assert_eq(record["hits"].size(), 1, "the flight still ended")
	assert_null(record["hits"][0]["target"], "the target behind the ground is not reached")


func test_without_an_impact_mask_a_shot_flies_through_walls() -> void:
	_wall(CollisionLayers.Mask.STRUCTURE_BLOCKER)
	await get_tree().physics_frame
	var emission: RecordingEmission = _emission(
		[
			_phase({"speed": 30.0}),
			_phase({"ends_on_arrival": false, "lifespan_seconds": 0.0, "applies_payload": true}),
		]
	)
	var record: Dictionary = await _run(emission)
	assert_almost_eq(record["hits"][0]["position"].x, AIM.x, 0.05, "the guided test alone")


func _wall(a_layer: int) -> Entity:
	var wall: Entity = Entity.new()
	var ownership: Ownership = Ownership.new()
	ownership.name = "Ownership"
	wall.add_child(ownership)
	wall.add_child(_box_shape())
	add_child_autofree(wall)
	wall.collision_layer = a_layer
	wall.global_position = Vector3(WALL_X, 0.0, 0.0)
	return wall


## A one-unit cube, centred on its body, spanning the flight line.
static func _box_shape() -> CollisionShape3D:
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3.ONE
	shape.shape = box
	return shape


## Hands EventSpawnEmission a commander and a map without a scenario around them.
class StubManager:
	extends ScenarioTriggerManager
	var commander: Commander

	func get_commander(_a_id: int) -> Commander:
		return commander


func test_a_spawn_event_puts_its_emission_where_it_stands() -> void:
	var manager: StubManager = StubManager.new()
	autofree(manager)
	manager.commander = Commander.new()
	add_child_autofree(manager.commander)
	manager.map = Map.new()
	autofree(manager.map)
	var event: EventSpawnEmission = EventSpawnEmission.new()
	event.emission_scene = FakePieces.emission_scene()
	add_child_autofree(event)
	event.global_position = Vector3(4.0, 0.0, 2.0)
	event.execute(manager)
	var spawned: Array = manager.commander.get_children().filter(
		func(c: Node) -> bool: return c is Entity and Payload.of(c) != null
	)
	assert_eq(spawned.size(), 1, "one emission, owned by the event's commander")
	assert_eq(spawned[0].global_position, event.global_position, "where the event stands")
	assert_eq(
		(spawned[0] as Entity).locomotion_component.goal_position,
		event.global_position,
		"and it lands there"
	)


## A phased mover cannot stop. When a homing shot's target leaves the game it keeps steering at
## where the target last was, looping round that point until its lifespan ends — it neither
## flies off on its last heading nor expires early.
func test_a_homing_shot_that_loses_its_target_circles_where_it_was() -> void:
	var quarry: Entity = _wall(0)
	quarry.global_position = AIM
	await get_tree().physics_frame
	var lifespan_seconds: float = 3.0
	var emission: RecordingEmission = _emission(
		[
			_phase(
				{
					"speed": 6.0,
					"turn_rate_degrees_per_second": 360.0,
					"lifespan_seconds": lifespan_seconds
				}
			),
		]
	)
	add_child(emission)
	emission.global_position = LAUNCH
	Emitter.launch(emission, null, quarry)
	var loss_tick: int = 10
	var settle_tick: int = 60
	var farthest_after_settling: float = 0.0
	var ticks: int = 0
	while is_instance_valid(emission) and ticks < MAX_TICKS:
		await get_tree().physics_frame
		ticks += 1
		if ticks == loss_tick:
			quarry.free()
		if ticks > settle_tick and is_instance_valid(emission):
			farthest_after_settling = maxf(
				farthest_after_settling, emission.global_position.distance_to(AIM)
			)
	assert_almost_eq(
		ticks,
		TimeUtils.ticks_from_seconds(lifespan_seconds),
		2,
		"it lives out its lifespan rather than arriving anywhere"
	)
	assert_lt(farthest_after_settling, 2.0, "it loops round the last place its target was")


## A garrisoned target is not freed: it leaves the tree and comes back. While it is held its
## position cannot be read, so the shot treats it as gone and keeps to where it was.
func test_a_homing_shot_whose_target_is_held_off_the_tree_circles_where_it_was() -> void:
	var quarry: Entity = _wall(0)
	quarry.global_position = AIM
	var quarry_parent: Node = quarry.get_parent()
	await get_tree().physics_frame
	var emission: RecordingEmission = _emission(
		[_phase({"speed": 6.0, "turn_rate_degrees_per_second": 360.0, "lifespan_seconds": 3.0})]
	)
	add_child(emission)
	emission.global_position = LAUNCH
	Emitter.launch(emission, null, quarry)
	var hold_tick: int = 10
	var settle_tick: int = 60
	var farthest_after_settling: float = 0.0
	var ticks: int = 0
	while is_instance_valid(emission) and ticks < MAX_TICKS:
		await get_tree().physics_frame
		ticks += 1
		if ticks == hold_tick:
			quarry_parent.remove_child(quarry)
		if ticks > settle_tick and is_instance_valid(emission):
			farthest_after_settling = maxf(
				farthest_after_settling, emission.global_position.distance_to(AIM)
			)
	quarry_parent.add_child(quarry)  # back in the tree, for autofree
	assert_lt(farthest_after_settling, 2.0, "it loops round the last place its target was")


func test_a_flight_slows_to_its_coast_speed_when_it_burns_out() -> void:
	# Paying out every tick records where the emission was each tick, so the step between two
	# records is its speed: fast while the motor burns, the coast speed after.
	var emission: RecordingEmission = _emission(
		[
			_phase(
				{
					"speed": 30.0,
					"burn_seconds": 0.2,
					"coast_speed": 6.0,
					"ends_on_arrival": false,
					"lifespan_seconds": 0.6,
					"applies_payload": true,
					"payload_period_seconds": 0.0
				}
			),
		]
	)
	var record: Dictionary = await _run(emission, Vector3(100.0, 0.0, 0.0))
	var hits: Array = record["hits"]
	var per_tick: float = 1.0 / TimeUtils.ticks_per_second()
	var early: float = hits[2]["position"].x - hits[1]["position"].x
	var late: float = hits[-1]["position"].x - hits[-2]["position"].x
	assert_almost_eq(early, 30.0 * per_tick, 0.001, "burning: full speed")
	assert_almost_eq(late, 6.0 * per_tick, 0.001, "burnt out: coast speed")


# --- Flight stages, lead ----------------------------------------------------------------


## A target that moves a fixed step every physics tick, and can be turned mid-flight.
class SteadyQuarry:
	extends Entity
	var step: Vector3 = Vector3.ZERO

	func _physics_process(_a_delta: float) -> void:
		global_position += step


func _quarry(a_position: Vector3, a_speed: float) -> SteadyQuarry:
	var quarry: SteadyQuarry = SteadyQuarry.new()
	var ownership: Ownership = Ownership.new()
	ownership.name = "Ownership"
	quarry.add_child(ownership)
	add_child_autofree(quarry)
	quarry.global_position = a_position
	quarry.step = Vector3(0.0, 0.0, a_speed / TimeUtils.ticks_per_second())
	return quarry


## Fires a steered rocket at a quarry crossing its line at 4 u/s, which reverses at `a_juke_tick`
## (never, at -1). Returns the payload's record.
func _fire_at_crossing_quarry(a_lead: float, a_juke_tick: int) -> Dictionary:
	var quarry: SteadyQuarry = _quarry(Vector3(8.0, 0.0, 0.0), 4.0)
	var emission: RecordingEmission = _emission(
		[
			_phase(
				{
					"speed": 12.0,
					"turn_rate_degrees_per_second": 360.0,
					"lead_fraction": a_lead,
					"lifespan_seconds": 2.0
				}
			),
			_phase({"ends_on_arrival": false, "lifespan_seconds": 0.0, "applies_payload": true}),
		]
	)
	add_child(emission)
	emission.global_position = LAUNCH
	Emitter.launch(emission, null, quarry)
	var hits: Array[Dictionary] = _payload(emission).hits
	var ticks: int = 0
	while is_instance_valid(emission) and ticks < MAX_TICKS:
		await get_tree().physics_frame
		ticks += 1
		if ticks == a_juke_tick:
			quarry.step = -quarry.step
	if is_instance_valid(emission):
		emission.queue_free()
	return hits[0]


func test_a_leading_shot_meets_a_target_that_holds_its_course() -> void:
	var hit: Dictionary = await _fire_at_crossing_quarry(1.0, -1)
	assert_lt(hit["miss"], 0.6, "it flew to where the target was going, and met it there")


func test_a_leading_shot_misses_a_target_that_turns_after_it_is_fired() -> void:
	var hit: Dictionary = await _fire_at_crossing_quarry(1.0, 4)
	assert_gt(hit["miss"], 2.0, "it flew on to the predicted point, which the target never reached")


func test_a_pursuing_shot_follows_a_target_that_turns() -> void:
	var hit: Dictionary = await _fire_at_crossing_quarry(0.0, 4)
	assert_lt(hit["miss"], 0.6, "no lead: it steers at the target itself, wherever it goes")


## Speeds recorded per tick, by phase: every phase pays out every tick, before that tick's move,
## so the step between two records is the speed — and a stage's first record still measures the
## stage before it. Its first own step is its second record.
func _stage_speeds(a_second: EmissionPhase) -> Dictionary:
	var first: EmissionPhase = _phase(
		{
			"speed": 30.0,
			"ends_on_arrival": false,
			"lifespan_seconds": 0.2,
			"applies_payload": true,
			"payload_period_seconds": 0.0
		}
	)
	a_second.ends_on_arrival = false
	a_second.lifespan_seconds = 0.2
	a_second.applies_payload = true
	a_second.payload_period_seconds = 0.0
	var record: Dictionary = await _run(_emission([first, a_second]), Vector3(100.0, 0.0, 0.0))
	var hits: Array = record["hits"]
	var speeds: Dictionary = {}
	for i: int in range(1, hits.size()):
		speeds[i] = {
			"phase": hits[i]["phase"],
			"step": hits[i]["position"].distance_to(hits[i - 1]["position"])
		}
	var second_stage: Array = speeds.values().filter(
		func(s: Dictionary) -> bool: return s["phase"] == 1
	)
	return {"first_step": second_stage[1]["step"], "last_step": second_stage[-1]["step"]}


func test_a_steered_stage_takes_over_the_flight_rather_than_relaunching() -> void:
	# Relaunched, it would leave at a tenth of its speed; it carries on at the speed it was handed.
	var steps: Dictionary = await _stage_speeds(
		_phase({"speed": 30.0, "turn_rate_degrees_per_second": 90.0, "launch_speed_ratio": 0.1})
	)
	assert_almost_eq(steps["first_step"], 30.0 / TimeUtils.ticks_per_second(), 0.001)


func test_a_straight_stage_flies_at_its_own_speed() -> void:
	var steps: Dictionary = await _stage_speeds(_phase({"speed": 6.0}))
	assert_almost_eq(steps["first_step"], 6.0 / TimeUtils.ticks_per_second(), 0.001)
	assert_almost_eq(steps["last_step"], 6.0 / TimeUtils.ticks_per_second(), 0.001)


func test_a_contact_skips_the_remaining_flight_stages_to_the_burst() -> void:
	var wall: Entity = _wall(CollisionLayers.Mask.STRUCTURE_BLOCKER)
	await get_tree().physics_frame
	var emission: RecordingEmission = _emission(
		[
			_phase({"speed": 30.0, "impact_mask": CollisionLayers.Mask.STRUCTURE_BLOCKER}),
			# A second stage that would fly straight through the wall, if it ever ran.
			_phase({"speed": 30.0, "ends_on_arrival": false, "lifespan_seconds": 0.5}),
			_phase({"ends_on_arrival": false, "lifespan_seconds": 0.0, "applies_payload": true}),
		]
	)
	var record: Dictionary = await _run(emission)
	assert_eq(record["hits"].size(), 1)
	assert_eq(record["hits"][0]["phase"], 2, "straight to the burst")
	assert_eq(record["hits"][0]["target"], wall)
	assert_almost_eq(record["hits"][0]["position"].x, WALL_X - 0.5, 0.05, "at the contact")


# --- Losing the lock ----------------------------------------------------------------------


func test_a_rocket_that_loses_its_lock_falls_to_the_ground_instead_of_expiring() -> void:
	var ground: StaticBody3D = StaticBody3D.new()
	ground.collision_layer = CollisionLayers.Mask.TERRAIN
	var slab: CollisionShape3D = _box_shape()
	(slab.shape as BoxShape3D).size = Vector3(200.0, 1.0, 200.0)
	slab.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(slab)
	add_child_autofree(ground)
	var quarry: Entity = _wall(0)
	quarry.global_position = Vector3(8.0, 0.0, 0.0)
	await get_tree().physics_frame
	var lifespan: float = 0.2
	var emission: RecordingEmission = _emission(
		[
			# Out of lock range from the start: no steering, no thrust, just a fall.
			_phase(
				{
					"speed": 10.0,
					"turn_rate_degrees_per_second": 360.0,
					"lock_range": 3.0,
					"lifespan_seconds": lifespan
				}
			),
			# A homing stage with no lock limit, which a cut motor never reaches.
			_phase({"speed": 10.0, "turn_rate_degrees_per_second": 360.0, "lifespan_seconds": 2.0}),
			_phase({"ends_on_arrival": false, "lifespan_seconds": 0.0, "applies_payload": true}),
		]
	)
	var payload: RecordingPayload = _payload(emission)
	payload.hitscan = false  # a free flight, which a contact ends
	var blast: CollisionShape3D = CollisionShape3D.new()
	blast.name = "HitShape"
	blast.shape = SphereShape3D.new()
	emission.add_child(blast)
	add_child(emission)
	emission.global_position = Vector3(0.0, 2.0, 0.0)
	Emitter.launch(emission, null, quarry)
	var hits: Array[Dictionary] = payload.hits
	var ticks: int = 0
	while is_instance_valid(emission) and ticks < MAX_TICKS:
		await get_tree().physics_frame
		ticks += 1
	if is_instance_valid(emission):
		emission.queue_free()
	assert_eq(hits.size(), 1, "it burst once")
	assert_eq(hits[0]["phase"], 2, "straight to the burst, skipping the homing stage")
	assert_almost_eq(hits[0]["position"].y, 0.0, 0.05, "on the ground, where the fall ended")
	assert_gt(ticks, TimeUtils.ticks_from_seconds(lifespan), "after its lifespan would have ended")
