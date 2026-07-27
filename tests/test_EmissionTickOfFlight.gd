extends GutTest

## The tick-of-flight rule: an emission never applies a payload on the physics tick it was
## created, whatever would otherwise end its flight at once. Two units that open fire on the
## same tick must both resolve their shots, so they can kill each other — a shot resolved at
## launch would let whichever fired first survive. See gdd/systems/combat/projectiles.md
## §Impact.
##
## Each case spawns the emission from inside another node's _physics_process, which is where
## every real emitter (Weapon, Ability, Interact) creates one.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gtest=res://tests/test_EmissionTickOfFlight.gd -gdir=res://tests/none -gexit

const SETTLE_TICKS: int = 4


## Records the physics frame of every payload application instead of applying one. The
## record lives on the emitter, because the emission frees itself when its lifespan ends.
class RecordingPayload extends Payload:
	var hit_frames: Array[int]

	func apply() -> void:
		hit_frames.append(Engine.get_physics_frames())


## Spawns one emission from its own physics tick, aimed at its own position: a flight phase
## `configure` shapes, then a one-tick impact that applies the payload.
class Shooter extends Node3D:
	var hit_frames: Array[int] = []
	var spawn_frame: int = -1
	var configure: Callable
	## Also run the emission's own tick at once, on the frame that created it — what any
	## emitter processed after its emission, or any launch-time fast path, would do.
	var ticks_at_once: bool = false

	func _physics_process(_a_delta: float) -> void:
		if spawn_frame >= 0:
			return
		spawn_frame = Engine.get_physics_frames()
		var emission: Entity = Entity.new()
		var payload: RecordingPayload = RecordingPayload.new()
		payload.name = "Payload"
		payload.hitscan = true
		payload.hit_frames = hit_frames
		emission.add_child(payload)
		var ownership: Ownership = Ownership.new()
		ownership.name = "Ownership"
		emission.add_child(ownership)
		var locomotion: PhasedLocomotion = PhasedLocomotion.new()
		locomotion.name = "Locomotion"
		emission.add_child(locomotion)
		var flight: EmissionPhase = EmissionPhase.new()
		var impact: EmissionPhase = EmissionPhase.new()
		impact.ends_on_arrival = false
		impact.lifespan_seconds = 0.0
		impact.applies_payload = true
		configure.call(flight)
		emission.add_child(flight)
		emission.add_child(impact)
		add_child(emission)
		Emitter.launch(emission, null, emission.global_position)
		if ticks_at_once:
			locomotion._physics_process(0.0)


func _fire(a_configure: Callable, a_ticks_at_once: bool = false) -> Shooter:
	var emitter: Shooter = Shooter.new()
	emitter.configure = a_configure
	emitter.ticks_at_once = a_ticks_at_once
	add_child_autofree(emitter)
	for _i: int in SETTLE_TICKS:
		await get_tree().physics_frame
	return emitter


func _assert_no_hit_on_creation_tick(a_emitter: Shooter) -> void:
	assert_gt(a_emitter.spawn_frame, -1, "the emitter spawned its emission")
	var frames: Array[int] = a_emitter.hit_frames
	assert_false(frames.is_empty(), "the payload was applied once the tick had passed")
	for frame: int in frames:
		assert_gt(frame, a_emitter.spawn_frame, "no payload on the tick of creation")


func test_a_point_blank_shot_waits_a_tick() -> void:
	# LINEAR "arrives" when within one step of its destination; aimed at its own muzzle it has
	# arrived before it has moved.
	var emitter: Shooter = await _fire(func(a_flight: EmissionPhase) -> void:
		a_flight.speed = 30.0)
	_assert_no_hit_on_creation_tick(emitter)


func test_an_expired_lifespan_waits_a_tick() -> void:
	# The shortest flight there is — one tick — never lands on the tick it was fired.
	var emitter: Shooter = await _fire(func(a_flight: EmissionPhase) -> void:
		a_flight.speed = 0.0
		a_flight.lifespan_seconds = 0.0)
	_assert_no_hit_on_creation_tick(emitter)


func test_a_shot_ticked_on_its_creation_frame_still_waits() -> void:
	# The two cases above hold today because Godot does not tick a node on the frame it was
	# added. This one removes that luck, so only the emission's own rule can pass it.
	var emitter: Shooter = await _fire(func(a_flight: EmissionPhase) -> void:
		a_flight.speed = 30.0, true)
	_assert_no_hit_on_creation_tick(emitter)
