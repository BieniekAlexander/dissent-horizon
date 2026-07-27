extends GutTest

## The EXPIRING facet — one implementation for every piece that leaves play on a timer (the
## Recon Drone and the Beacon), authored in seconds.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_Lifespan.gd -gexit

const DRONE_PATH: String = "res://scenes/entities/nt_aircraftLight_recon.tscn"

## Seconds used where the value itself does not matter, only that it is a whole number of
## ticks at any sensible physics rate.
const SOME_SECONDS: float = 1.0


func _drone() -> Entity:
	var drone: Entity = (load(DRONE_PATH) as PackedScene).instantiate()
	return drone


func _beacon() -> Entity:
	return Beacon.SCENE.instantiate() as Entity


## Drive the component's own tick `a_ticks` times, as the physics server would.
func _tick(a_lifespan: Lifespan, a_ticks: int) -> void:
	for _i: int in a_ticks:
		a_lifespan._physics_process(1.0 / TimeUtils.ticks_per_second())


func test_a_negative_duration_attaches_nothing() -> void:
	# Permanence is the ABSENCE of the component, not a sentinel inside it.
	var drone := _drone()
	add_child_autofree(drone)
	assert_null(Lifespan.attach(drone, -1.0))
	assert_null(drone.get_node_or_null("Lifespan"))


func test_a_duration_attaches_a_named_component_in_seconds() -> void:
	var drone := _drone()
	add_child_autofree(drone)
	var lifespan := Lifespan.attach(drone, SOME_SECONDS)
	assert_eq(drone.get_node_or_null("Lifespan"), lifespan)
	assert_eq(lifespan.lifespan_seconds, SOME_SECONDS)


func test_the_host_stands_until_the_last_tick_and_goes_on_it() -> void:
	var drone := _drone()
	add_child_autofree(drone)
	var lifespan := Lifespan.attach(drone, SOME_SECONDS)
	var ticks: int = TimeUtils.ticks_from_seconds(SOME_SECONDS)
	_tick(lifespan, ticks - 1)
	assert_false(drone.is_queued_for_deletion(), "one tick short, it is still standing")
	_tick(lifespan, 1)
	assert_true(drone.is_queued_for_deletion(), "and on the last tick it leaves")


func test_an_expiring_beacon_announces_itself() -> void:
	# A Beacon's spotter must hear it go however it goes — the component signals as its host
	# is freed, so a plain expiry needs no override on the host.
	var beacon := _beacon()
	add_child_autofree(beacon)
	var component: Beacon = Beacon.of(beacon)
	var heard: Array[bool] = []
	component.spent.connect(func() -> void: heard.append(true))
	var lifespan := Lifespan.attach(beacon, SOME_SECONDS)
	_tick(lifespan, TimeUtils.ticks_from_seconds(SOME_SECONDS))
	assert_true(beacon.is_queued_for_deletion(), "it leaves")
	assert_true(component.is_leaving(), "and a scan already skips it")
	beacon.free()
	assert_eq(heard, [true], "the spotter hears it go, once")


func test_it_expires_once() -> void:
	# Ticking past the end must not call expire() again on a host already leaving.
	var beacon := _beacon()
	add_child_autofree(beacon)
	watch_signals(beacon)
	var lifespan := Lifespan.attach(beacon, SOME_SECONDS)
	_tick(lifespan, TimeUtils.ticks_from_seconds(SOME_SECONDS))
	assert_false(lifespan.is_physics_processing(), "it stops counting once spent")
