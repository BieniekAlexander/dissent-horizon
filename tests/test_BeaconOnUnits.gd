extends GutTest

## Beacons that ride on units, beacons a shot has claimed, beacon secrecy, and the shell that
## follows its beacon — the static-defence build-out of the Colonial bombardment system.
## Rules: gdd/systems/combat/bombardment.md §Beacons; why: gdd/design-framework/static-defence.md.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_BeaconOnUnits.gd -gexit

const OWN: int = 1
const FOE: int = 2

## Scenes are loaded inside the tests rather than preloaded at file scope (CLAUDE.md §A
## file-scope preload of an entity scene in a test can poison the whole run).
const MECH_GROUND: Dictionary = FakePieces.MACHINE
const MECH_AIR: Dictionary = {"aerial": true, "vision": 8.0, "frame": Defense.FrameType.MECH}
const BIO_GROUND: Dictionary = {"speed": 2.0, "vision": 8.0, "abilities": [{"grants": [&"spot"]}]}
const STRUCTURE: Dictionary = FakePieces.BUILDING


## Answers the one map question beacon placement asks.
class StubMap:
	extends Map

	func terrain_height_at(_a_world_xz: Vector2) -> float:
		return 0.0


var _commanders: Dictionary = {}
var _map: Map


func before_each() -> void:
	FakePieces.install_emitting_ability(Bombard.ABILITY_ID, {"range": 100.0})
	FakePieces.install_ability(&"spot", {"range": 30.0})
	_commanders = {}


func after_each() -> void:
	FakePieces.restore_abilities()
	if _map != null and is_instance_valid(_map):
		_map.free()
		_map = null


func _commander(a_id: int) -> Commander:
	if not _commanders.has(a_id):
		var commander := Commander.new()
		commander.id = a_id
		add_child_autofree(commander)
		_commanders[a_id] = commander
	return _commanders[a_id]


func _at(a_xz: Vector2) -> Vector3:
	return Vector3(a_xz.x, 0.0, a_xz.y)


func _piece(a_options: Dictionary, a_commander_id: int, a_xz: Vector2) -> Commandable:
	var piece: Commandable = FakePieces.make(a_options)
	_commander(a_commander_id).add_child(piece)
	autofree(piece)
	piece.top_level = true
	piece.ownership.commander = _commander(a_commander_id)
	piece.global_position = _at(a_xz)
	return piece


func _beacon(a_commander_id: int, a_xz: Vector2) -> Beacon:
	var piece: Entity = Beacon.SCENE.instantiate()
	add_child_autofree(piece)
	piece.top_level = true
	piece.ownership.commander = _commander(a_commander_id)
	piece.global_position = _at(a_xz)
	return Beacon.of(piece)


# --- Who can carry one --------------------------------------------------------------


func test_a_grounded_mech_unit_can_carry_a_beacon() -> void:
	assert_true(Beacon.can_carry(_piece(MECH_GROUND, FOE, Vector2.ZERO)))


func test_a_bio_unit_cannot() -> void:
	assert_false(Beacon.can_carry(_piece(BIO_GROUND, FOE, Vector2.ZERO)))


func test_an_aircraft_cannot() -> void:
	assert_false(Beacon.can_carry(_piece(MECH_AIR, FOE, Vector2.ZERO)))


func test_a_structure_cannot() -> void:
	assert_false(Beacon.can_carry(_piece(STRUCTURE, FOE, Vector2.ZERO)))


func test_nothing_cannot() -> void:
	assert_false(Beacon.can_carry(null))


# --- Riding along --------------------------------------------------------------------


func test_an_attached_beacon_moves_with_its_carrier() -> void:
	var tank := _piece(MECH_GROUND, FOE, Vector2(10, 10))
	var beacon := _beacon(OWN, Vector2(0, 0))
	assert_true(beacon.attach_to(tank))
	tank.global_position = _at(Vector2(14, 10))
	beacon._physics_process(0.0)
	assert_almost_eq(beacon.host().global_position.x, 14.0, 0.001)
	assert_eq(beacon.carrier(), tank)


func test_attaching_to_something_that_cannot_carry_changes_nothing() -> void:
	var soldier := _piece(BIO_GROUND, FOE, Vector2(10, 10))
	var beacon := _beacon(OWN, Vector2(0, 0))
	assert_false(beacon.attach_to(soldier))
	assert_null(beacon.carrier())
	assert_almost_eq(beacon.host().global_position.x, 0.0, 0.001, "it stays where it stood")


func test_a_beacon_outlives_its_carrier_where_it_last_was() -> void:
	var tank := _piece(MECH_GROUND, FOE, Vector2(10, 10))
	var beacon := _beacon(OWN, Vector2(0, 0))
	beacon.attach_to(tank)
	tank.free()
	beacon._physics_process(0.0)
	assert_null(beacon.carrier())
	assert_false(beacon.is_leaving(), "a carrier's death leaves a point beacon behind")
	assert_almost_eq(beacon.host().global_position.x, 10.0, 0.001)


# --- A shot claims its beacon --------------------------------------------------------


func test_a_used_beacon_cannot_be_spent_again() -> void:
	var beacon := _beacon(OWN, Vector2(60, 0))
	beacon.mark_used()
	assert_null(
		BombardTargeting.source_at(_commander(OWN), _at(Vector2(60, 0))),
		"a second battery may not claim a beacon a shell is already coming for"
	)
	assert_false(BombardTargeting.is_spotted(_commander(OWN), _at(Vector2(60, 0))))


func test_the_beacon_is_dismissed_when_the_shell_hands_over_to_its_impact() -> void:
	var beacon := _beacon(OWN, Vector2(0, 0))
	var shell: Entity = FakePieces.emission()
	autofree(shell)
	beacon.dismiss_on_landing(shell)
	var phased := shell.get_node("Locomotion") as PhasedLocomotion
	phased.phase_entered.emit(0)
	assert_false(beacon.is_leaving(), "entering the flight phase is not landing")
	phased.phase_entered.emit(1)
	assert_true(beacon.is_leaving(), "entering the impact phase is")


func test_the_beacon_is_dismissed_when_the_shell_leaves_play() -> void:
	var beacon := _beacon(OWN, Vector2(0, 0))
	var shell: Entity = FakePieces.emission()
	add_child(shell)
	beacon.dismiss_on_landing(shell)
	shell.free()
	assert_true(beacon.is_leaving())


func test_a_shell_outliving_its_beacon_is_harmless() -> void:
	var beacon := _beacon(OWN, Vector2(0, 0))
	var shell: Entity = FakePieces.emission()
	add_child(shell)
	beacon.dismiss_on_landing(shell)
	beacon.host().free()
	(shell.get_node("Locomotion") as PhasedLocomotion).phase_entered.emit(1)
	shell.free()
	assert_true(true, "no call reached the freed beacon")


# --- The Bombard fires on a beacon --------------------------------------------------


func _gun() -> Commandable:
	_commander(OWN).add_infrastructure(1000)
	var gun := _piece(
		{
			"structure": true,
			"dimensions": Vector2i(2, 2),
			"beacon_range": 20.0,
			"abilities": [{"grants": [Bombard.ABILITY_ID]}]
		},
		OWN,
		Vector2.ZERO
	)
	gun.build_progress = 1.0
	if _map == null:
		_map = StubMap.new()
	gun.map = _map
	return gun


func test_firing_on_a_beacon_marks_it_used_and_leaves_it_standing() -> void:
	var gun := _gun()
	var beacon := _beacon(OWN, Vector2(60, 0))
	var order := Bombard.new(CommandMessage.new(null, null, null, _at(Vector2(60, 0))))
	order.fulfill_action(gun)
	assert_true(beacon.is_used(), "the shot claims the beacon")
	assert_false(beacon.is_leaving(), "and it stands until the shell lands")


func test_firing_on_ground_a_range_covers_claims_no_beacon() -> void:
	var gun := _gun()
	var beacon := _beacon(OWN, Vector2(5, 0))
	var order := Bombard.new(CommandMessage.new(null, null, null, _at(Vector2(5, 0))))
	order.fulfill_action(gun)
	assert_false(beacon.is_used(), "the gun's own range covered the point")


# --- Spotting a unit ------------------------------------------------------------------


func _recruit(a_xz: Vector2) -> Commandable:
	var recruit := _piece(BIO_GROUND, OWN, a_xz)
	if _map == null:
		_map = StubMap.new()
	recruit.map = _map
	return recruit


func _spot(a_actor: Commandable, a_target: Entity) -> Spot:
	var order := Spot.new(CommandMessage.new(null, a_target, null, a_target.global_position))
	for _i: int in Spot.CHANNEL_TICKS:
		order.fulfill_action(a_actor)
	return order


func test_spotting_an_enemy_tank_attaches_the_beacon_to_it() -> void:
	var recruit := _recruit(Vector2(0, 0))
	var tank := _piece(MECH_GROUND, FOE, Vector2(5, 0))
	var order := _spot(recruit, tank)
	assert_not_null(order._beacon)
	assert_eq(order._beacon.carrier(), tank)


func test_spotting_an_enemy_soldier_places_a_point_beacon() -> void:
	var recruit := _recruit(Vector2(0, 0))
	var soldier := _piece(BIO_GROUND, FOE, Vector2(5, 0))
	var order := _spot(recruit, soldier)
	assert_not_null(order._beacon)
	assert_null(order._beacon.carrier(), "bio units cannot carry a beacon")


func test_spotting_a_friendly_tank_places_a_point_beacon() -> void:
	var recruit := _recruit(Vector2(0, 0))
	var tank := _piece(MECH_GROUND, OWN, Vector2(5, 0))
	var order := _spot(recruit, tank)
	assert_null(order._beacon.carrier(), "only an enemy is tagged")


func test_a_carrier_driving_off_the_leash_drops_the_beacon() -> void:
	var recruit := _recruit(Vector2(0, 0))
	var tank := _piece(MECH_GROUND, FOE, Vector2(5, 0))
	var order := _spot(recruit, tank)
	order.fulfill_action(recruit)
	assert_false(order._beacon.is_leaving(), "within the leash it stands")
	tank.global_position = _at(Vector2(Spot.target_range(recruit) + 1.0, 0))
	order.fulfill_action(recruit)
	assert_true(order._beacon.is_leaving(), "past the leash it is dropped")


# --- Secrecy ---------------------------------------------------------------------------


func test_a_beacon_is_stealthed_until_detected() -> void:
	var beacon := _beacon(FOE, Vector2(0, 0))
	var stealth: Stealth = beacon.host().stealth
	assert_not_null(stealth, "a beacon carries stealth")
	beacon._physics_process(0.0)
	assert_eq(stealth.state, Stealth.State.STEALTHED)
	stealth.reveal()
	beacon._physics_process(0.0)
	assert_eq(stealth.state, Stealth.State.REVEALED)


func test_a_detector_can_find_a_beacon() -> void:
	var beacon := _beacon(FOE, Vector2(0, 0))
	await wait_physics_frames(2)
	var shape := SphereShape3D.new()
	shape.radius = 2.0
	var found: Array[Entity] = SU.query_shape_for_entities(
		beacon.host().get_world_3d(),
		shape,
		Transform3D(Basis(), _at(Vector2(0, 0))),
		CollisionLayers.Mask.STEALTH,
		[],
		8
	)
	assert_has(found, beacon.host(), "the stealth layer query a detector runs finds it")


func test_an_enemy_beacon_is_not_drawn_while_stealthed() -> void:
	var beacon := _beacon(FOE, Vector2(0, 0))
	beacon._physics_process(0.0)
	beacon._process(0.0)
	var visual := beacon.host().get_node("MeshVisual") as Node3D
	assert_eq(RTSController.PLAYER_COMMANDER_ID, OWN, "fixture: the local player is OWN")
	assert_false(visual.visible)


func test_your_own_beacon_is_always_drawn() -> void:
	var beacon := _beacon(OWN, Vector2(0, 0))
	beacon._physics_process(0.0)
	beacon._process(0.0)
	assert_true((beacon.host().get_node("MeshVisual") as Node3D).visible)


func test_the_used_marker_shows_only_to_the_owners_side() -> void:
	var mine := _beacon(OWN, Vector2(0, 0))
	var theirs := _beacon(FOE, Vector2(3, 0))
	for beacon: Beacon in [mine, theirs]:
		beacon.mark_used()
		beacon.host().stealth.reveal()
		beacon._physics_process(0.0)
		beacon._process(0.0)
	assert_true(mine.host().get_node("MeshVisual/UsedMarker").visible)
	assert_false(
		theirs.host().get_node("MeshVisual/UsedMarker").visible,
		"an opponent sees no change when a beacon is fired on"
	)


# --- The shell follows its goal -------------------------------------------------------


func _falling_phase(a_tracks: bool) -> EmissionPhase:
	var phase := EmissionPhase.new()
	autofree(phase)
	phase.speed = 9.0
	phase.gravity_mps2 = 4.5
	phase.tracks_goal = a_tracks
	return phase


func test_tracking_leaves_the_fall_alone() -> void:
	var phase := _falling_phase(true)
	var launched := phase.launch_velocity(Vector3.ZERO, Vector3(20, 0, 0))
	var tracked := phase.tracked_velocity(launched, Vector3.ZERO, Vector3(20, 0, 6))
	assert_almost_eq(tracked.y, launched.y, 0.0001, "only the horizontal is re-aimed")


func test_tracking_bends_toward_a_goal_that_moved() -> void:
	var phase := _falling_phase(true)
	var launched := phase.launch_velocity(Vector3.ZERO, Vector3(20, 0, 0))
	var tracked := phase.tracked_velocity(launched, Vector3.ZERO, Vector3(20, 0, 6))
	assert_gt(tracked.z, 0.0, "the flight turns after the goal")


func test_tracking_a_still_goal_keeps_roughly_the_launch_heading() -> void:
	var phase := _falling_phase(true)
	var goal := Vector3(20, 0, 5)
	var launched := phase.launch_velocity(Vector3.ZERO, goal)
	var tracked := phase.tracked_velocity(launched, Vector3.ZERO, goal)
	assert_almost_eq(
		VU.in_xz(tracked).normalized(), VU.in_xz(launched).normalized(), Vector2.ONE * 0.001
	)


func test_a_phase_that_does_not_track_is_left_alone() -> void:
	var phase := _falling_phase(false)
	var v := Vector3(1, 2, 3)
	assert_eq(phase.tracked_velocity(v, Vector3.ZERO, Vector3(20, 0, 6)), v)


func test_a_flight_with_no_goal_is_left_alone() -> void:
	var phase := _falling_phase(true)
	var v := Vector3(1, 2, 3)
	assert_eq(phase.tracked_velocity(v, Vector3.ZERO, null), v)


# --- Per-occupant garrison reach -------------------------------------------------------


func test_a_garrison_sets_reach_per_occupant_piece() -> void:
	var garrison := Garrison.new()
	autofree(garrison)
	garrison.range_bonus = 1.0
	garrison.reach_by_piece = {&"favoured": 12.0}
	var favoured := _piece(MECH_GROUND, OWN, Vector2.ZERO)
	favoured.id = &"favoured"
	var other := _piece(MECH_GROUND, OWN, Vector2.ZERO)
	assert_almost_eq(
		garrison.reach_bonus_for(favoured, 0.5),
		11.5,
		0.001,
		"the favoured piece fires at its set reach, whatever its own, and the host bonus is not added"
	)
	assert_almost_eq(
		garrison.reach_bonus_for(other, 0.5), 1.0, 0.001, "everyone else gets the host's"
	)


func test_a_set_reach_never_shortens_an_occupant() -> void:
	var garrison := Garrison.new()
	autofree(garrison)
	garrison.reach_by_piece = {&"favoured": 12.0}
	var favoured := _piece(MECH_GROUND, OWN, Vector2.ZERO)
	favoured.id = &"favoured"
	assert_eq(garrison.reach_bonus_for(favoured, 20.0), 0.0)


# --- In flight -------------------------------------------------------------------------


## A flat TERRAIN plane for a free flight to strike.
func _ground() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = CollisionLayers.Mask.TERRAIN
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	shape.shape = box
	body.add_child(shape)
	add_child_autofree(body)
	body.global_position = Vector3(0, -0.6, 0)  # its top just under y=0, where pieces stand


func test_a_shell_fired_on_a_moving_carrier_lands_on_it() -> void:
	_ground()
	var gun := _gun()
	var tank := _piece(MECH_GROUND, FOE, Vector2(40, 0))
	var beacon := _beacon(OWN, Vector2(40, 0))
	beacon.attach_to(tank)
	var order := Bombard.new(CommandMessage.new(null, null, null, _at(Vector2(40, 0))))
	order.fulfill_action(gun)
	assert_true(beacon.is_used())
	var landed_at: Variant = null
	for _frame: int in 30 * 20:
		tank.global_position += Vector3(0, 0, 3.0 / 30.0)  # 3 units a second, sideways
		await wait_physics_frames(1)
		if not is_instance_valid(beacon) or beacon.is_leaving():
			landed_at = tank.global_position
			break
	assert_not_null(landed_at, "the shell landed and dismissed its beacon")
	if landed_at != null:
		assert_gt((landed_at as Vector3).z, 3.0, "the tank had driven well off its start")
