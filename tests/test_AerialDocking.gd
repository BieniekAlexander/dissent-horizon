extends GutTest

## Tests for the FLIGHT half of docking: what `Aerial.land_at` does to each aerial mode, and
## — the point of these — that a FLYING unit can be grounded at all.
##
## FLYING had no landing regime before docking existed. It was unconditionally airborne,
## `_update_flying_height` owned the altitude and pushed it back to cruise every tick, and
## an idle one orbited rather than stopping. Docking one is therefore not "reuse the hover
## landing" but "suspend normal flight", and these pin the three places that has to hold.
##
## Driven by calling `_physics_process` directly rather than by running the scene tree, so
## no Map, no NavigationServer and no scenario are needed — the landing state machine is
## pure altitude bookkeeping and does not consult any of them.

## Generous enough to cover the acceleration-limited descent from AERIAL_HEIGHT at
## LANDING_SPEED with room to spare, so a test never fails merely for being impatient.
const MAX_TICKS: int = 600

const SpecRegistry := preload("res://tools/spec_import/spec_registry.gd")


## A piece's locomotion, with an Aerial in `a_mode` beside it (none for GROUNDED) and a
## Docking unless `a_docks` is false. The Aerial goes in first: Movement settles whether it
## flies the first time it is asked once it is in the tree.
func _flier(a_mode: Movement.Mode, a_docks: bool = true) -> Movement:
	var body := Node3D.new()
	add_child_autofree(body)
	if a_mode != Movement.Mode.GROUNDED:
		var aerial := Aerial.new()
		aerial.name = "Aerial"
		aerial.mode = a_mode
		body.add_child(aerial)
		if a_docks:
			var docking := Docking.new()
			docking.name = "Docking"
			body.add_child(docking)
	var m := Movement.new()
	m.name = "Locomotion"
	m.speed = 3.0
	body.add_child(m)
	return m


func _air(a_m: Movement) -> Aerial:
	return a_m.get_parent().get_node("Aerial") as Aerial


## Tick the unit until `predicate` holds, returning the ticks taken (-1 on timeout).
func _tick_until(a_movement: Movement, a_predicate: Callable) -> int:
	for i in MAX_TICKS:
		if a_predicate.call():
			return i
		_air(a_movement)._physics_process(1.0 / 30.0)
	return -1 if not a_predicate.call() else MAX_TICKS


#region A FLYING unit can be grounded
func test_a_flying_unit_starts_airborne_at_cruise_altitude() -> void:
	var m := _flier(Movement.Mode.FLYING)
	assert_true(_air(m).is_airborne(), "a jet is airborne until something lands it")
	assert_eq(_air(m).height_offset(), Aerial.AERIAL_HEIGHT, "at cruise altitude")


func test_land_at_grounds_a_flying_unit() -> void:
	# The whole point: before docking, nothing could put a FLYING unit on the ground.
	var m := _flier(Movement.Mode.FLYING)
	_air(m).land_at(Vector3.ZERO, 0.0, Callable())
	var ticks: int = _tick_until(m, func() -> bool: return _air(m).is_docked())
	assert_gt(ticks, 0, "it took a real descent, not a teleport")
	assert_ne(ticks, -1, "a FLYING unit reaches the deck")
	assert_true(_air(m).is_docked(), "and is parked on it")
	assert_false(_air(m).is_airborne(), "a parked jet is not airborne")
	assert_almost_eq(_air(m).height_offset(), 0.0, 0.001, "sitting at deck level")


func test_a_parked_jet_is_shot_at_as_a_ground_target() -> void:
	# is_airborne() is read by Weapon.get_range_for_target to pick the air or ground range.
	# A plane on a deck being immune to anything that cannot shoot upward would be a
	# considerable exploit, and is why is_airborne() stopped being unconditional for FLYING.
	var m := _flier(Movement.Mode.FLYING)
	_air(m).land_at(Vector3.ZERO, 0.0, Callable())
	_tick_until(m, func() -> bool: return _air(m).is_docked())
	assert_false(_air(m).is_airborne(), "ground target while parked")


func test_a_parked_jet_does_not_orbit() -> void:
	# CommandReceiver feeds compute_orbit_velocity() to any idle FLYING unit every tick, so
	# without the gate a plane whose docking order ended would taxi off its pad in a circle.
	var m := _flier(Movement.Mode.FLYING)
	_air(m).land_at(Vector3.ZERO, 0.0, Callable())
	_tick_until(m, func() -> bool: return _air(m).is_docked())
	assert_eq(_air(m).compute_orbit_velocity(), Vector3.ZERO, "a parked plane holds still")


func test_flight_height_control_does_not_fight_the_descent() -> void:
	# _update_flying_height pushes the offset back to AERIAL_HEIGHT every tick it runs, so
	# a descent that did not suspend it would never reach the ground. Pinned by watching the
	# altitude fall monotonically rather than by reaching in at the routing.
	var m := _flier(Movement.Mode.FLYING)
	_air(m).land_at(Vector3.ZERO, 0.0, Callable())
	var previous: float = _air(m).height_offset()
	for i in MAX_TICKS:
		_air(m)._physics_process(1.0 / 30.0)
		assert_true(
			_air(m).height_offset() <= previous + 0.0001,
			"altitude never climbs back during a descent"
		)
		previous = _air(m).height_offset()
		if _air(m).is_docked():
			break
	assert_true(_air(m).is_docked(), "and the descent completes")


#endregion


#region Taking off again
func test_a_flying_unit_returns_to_cruise_altitude() -> void:
	var m := _flier(Movement.Mode.FLYING)
	_air(m).land_at(Vector3.ZERO, 0.0, Callable())
	_tick_until(m, func() -> bool: return _air(m).is_docked())
	_air(m).take_off()
	var ticks: int = _tick_until(m, func() -> bool: return _air(m).is_airborne())
	assert_ne(ticks, -1, "it climbs back out")
	assert_almost_eq(_air(m).height_offset(), Aerial.AERIAL_HEIGHT, 0.001, "to cruise altitude")
	assert_false(_air(m).is_docked(), "and is no longer on a pad")


func test_taking_off_restores_normal_flight() -> void:
	# Once airborne the plane must orbit again, or an idle jet that had docked once would
	# hang motionless in the air forever.
	var m := _flier(Movement.Mode.FLYING)
	_air(m).land_at(Vector3.ZERO, 0.0, Callable())
	_tick_until(m, func() -> bool: return _air(m).is_docked())
	_air(m).take_off()
	_tick_until(m, func() -> bool: return _air(m).is_airborne())
	assert_ne(_air(m).compute_orbit_velocity(), Vector3.ZERO, "normal flight resumes")


func test_a_landing_is_forgotten_once_the_unit_leaves_the_deck() -> void:
	# The deck offset must not survive to raise the unit's resting height the next time it
	# sets down, and the pad flag must not survive to suppress the navmesh safeguards.
	var m := _flier(Movement.Mode.FLYING)
	_air(m).land_at(Vector3.ZERO, 1.5, Callable())
	_tick_until(m, func() -> bool: return _air(m).is_docked())
	assert_almost_eq(_air(m).height_offset(), 1.5, 0.001, "resting on a raised deck")
	_air(m).take_off()
	_tick_until(m, func() -> bool: return _air(m).is_airborne())
	_air(m).land_at(Vector3.ZERO, 0.0, Callable())
	_tick_until(m, func() -> bool: return _air(m).is_docked())
	assert_almost_eq(_air(m).height_offset(), 0.0, 0.001, "the old deck height is gone")


#endregion


#region Deck height
func test_a_raised_deck_stops_the_descent_above_the_ground() -> void:
	# DockingPad.deck_height is what lets a pad sit on a raised structure rather than
	# having the aircraft sink through it to ground level.
	for mode: Movement.Mode in [Movement.Mode.FLYING, Movement.Mode.HOVERING]:
		var m := _flier(mode)
		_air(m).land_at(Vector3.ZERO, 2.0, Callable())
		var ticks: int = _tick_until(m, func() -> bool: return _air(m).is_docked())
		assert_ne(ticks, -1, "mode %d reaches its deck" % mode)
		assert_almost_eq(
			_air(m).height_offset(), 2.0, 0.001, "mode %d rests on the deck, not the ground" % mode
		)


#endregion


#region Both modes, and only aerial ones
func test_both_aerial_modes_dock() -> void:
	# The mechanic is not helicopter-only. What differs between the modes is only where the
	# descent BEGINS (see Rearm._approach_radius), not whether it can happen.
	for mode: Movement.Mode in [Movement.Mode.FLYING, Movement.Mode.HOVERING]:
		var m := _flier(mode)
		_air(m).land_at(Vector3.ZERO, 0.0, Callable())
		assert_ne(
			_tick_until(m, func() -> bool: return _air(m).is_docked()), -1, "mode %d docks" % mode
		)


func test_land_at_reports_completion_through_its_callback() -> void:
	var m := _flier(Movement.Mode.FLYING)
	var called: Array[bool] = [false]
	_air(m).land_at(Vector3.ZERO, 0.0, func() -> void: called[0] = true)
	assert_false(called[0], "not on the way down")
	_tick_until(m, func() -> bool: return _air(m).is_docked())
	assert_true(called[0], "fired on touchdown")


#endregion


#region Opting out of airfields entirely
func test_an_opted_out_aircraft_cannot_be_grounded() -> void:
	# The kamikaze guarantee: it spawns airborne and stays that way. land_at is the last
	# line of it — even a caller that got here without checking cannot put it down.
	var m := _flier(Movement.Mode.FLYING, false)
	_air(m).land_at(Vector3.ZERO, 0.0, Callable())
	_tick_until(m, func() -> bool: return _air(m).is_docked())
	assert_false(_air(m).is_docked(), "it never reaches a deck")
	assert_true(_air(m).is_airborne(), "and never leaves cruise altitude")
	assert_eq(_air(m).height_offset(), Aerial.AERIAL_HEIGHT, "still flying")


func test_an_opted_out_aircraft_keeps_flying_normally() -> void:
	# Opting out must cost it nothing else: it still orbits, still cruises.
	var m := _flier(Movement.Mode.FLYING, false)
	_air(m).land_at(Vector3.ZERO, 0.0, Callable())
	for i in 30:
		_air(m)._physics_process(1.0 / 30.0)
	assert_ne(_air(m).compute_orbit_velocity(), Vector3.ZERO, "normal flight is untouched")


func test_docking_without_flight_is_refused_at_import() -> void:
	# Every dock today is a deck an aircraft lands on, so a jeep that says it docks would be
	# let in by the airfield and then have no way onto it.
	var registry := SpecRegistry.new()
	registry._validate_docking({"_doc_path": "doc.md", "id": "jeep", "docking": true})
	assert_eq(registry.errors.size(), 1, "docking needs aerial")
	registry = SpecRegistry.new()
	registry._validate_docking(
		{"_doc_path": "doc.md", "id": "jet", "docking": true, "aerial": {"mode": "FLYING"}}
	)
	assert_eq(registry.errors, [], "an aircraft may dock")


func test_land_at_still_reports_completion_for_an_opted_out_unit() -> void:
	# A caller waiting on the callback must not hang just because the unit refused.
	var m := _flier(Movement.Mode.FLYING, false)
	var called: Array[bool] = [false]
	_air(m).land_at(Vector3.ZERO, 0.0, func() -> void: called[0] = true)
	assert_true(called[0], "it reports itself arrived and stays put")


#endregion


#region The approach distance
func test_a_faster_aircraft_commits_to_its_descent_earlier() -> void:
	# Speed-blind constants make a fast aircraft arrive still at altitude — the same
	# reasoning behind Movement._dive_commit_distance. Derived, so a rebalance carries.
	var slow := _flier(Movement.Mode.FLYING)
	slow.speed = 2.0
	var fast := _flier(Movement.Mode.FLYING)
	fast.speed = 8.0
	assert_gt(
		_air(fast).descent_run_distance(0.0),
		_air(slow).descent_run_distance(0.0),
		"the faster jet begins its approach further out"
	)


func test_a_higher_deck_shortens_the_run_in() -> void:
	var m := _flier(Movement.Mode.FLYING)
	assert_lt(
		_air(m).descent_run_distance(3.0),
		_air(m).descent_run_distance(0.0),
		"less altitude to shed is less ground covered shedding it"
	)


#endregion


#region Parking without flying in
## An aircraft ROLLED OUT by the airfield that built it belongs on the deck from its first
## frame, not hanging in the air over its own hangar. park_on_deck is the end state of
## land_at entered directly.
func test_park_on_deck_grounds_a_flier_outright() -> void:
	var m: Movement = _flier(Movement.Mode.FLYING)
	assert_true(_air(m).is_airborne(), "it starts at cruise")
	_air(m).park_on_deck(0.0)
	assert_true(_air(m).is_docked(), "and is parked immediately, with no descent to fly")
	assert_false(_air(m).is_airborne())
	assert_eq(_air(m).height_offset(), 0.0, "sitting on the deck, not above it")


## A raised deck is authored per pad, so parking has to honour it exactly as landing does.
func test_park_on_deck_honours_the_deck_height() -> void:
	var m: Movement = _flier(Movement.Mode.HOVERING)
	_air(m).park_on_deck(1.25)
	assert_true(_air(m).is_docked())
	assert_eq(_air(m).height_offset(), 1.25)


## Parked is not stranded: the same take_off that lifts a unit which flew in lifts one that
## was rolled out, which is what lets an order get it off the pad.
func test_a_parked_flier_can_still_take_off() -> void:
	var m: Movement = _flier(Movement.Mode.FLYING)
	_air(m).park_on_deck(0.0)
	_air(m).take_off()
	assert_ne(
		_tick_until(m, func() -> bool: return _air(m).is_airborne()), -1, "it climbs back to cruise"
	)


## The last line of the kamikaze's "spawns airborne, stays airborne" guarantee. It reaches
## park_on_deck through Production like any other aircraft, so the refusal has to be here.
func test_a_flier_that_opts_out_of_airfields_cannot_be_parked() -> void:
	var m: Movement = _flier(Movement.Mode.FLYING, false)
	_air(m).park_on_deck(0.0)
	assert_false(_air(m).is_docked(), "docks: false means no deck, however it was asked")


#endregion


#region Holding still
## The distinction the whole attack run is built on: a fixed wing cannot stop, so it must
## not be told to. Everything else can.
func test_only_a_fixed_wing_cannot_hold_still() -> void:
	assert_false(
		_flier(Movement.Mode.FLYING).can_hold_still(), "an aeroplane has no hover to stop in"
	)
	assert_true(
		_flier(Movement.Mode.HOVERING).can_hold_still(),
		"a gunship holds station — that is the difference between the two aerial modes"
	)
	assert_true(_flier(Movement.Mode.GROUNDED).can_hold_still())


#endregion


#region Turning around
## THE REVERSAL BLIND SPOT. Vector3.slerp builds its axis from a cross product, which is
## zero for exactly opposite vectors — so a unit asked to turn 180° got its own heading
## back and flew straight on forever. An aircraft that has overflown its target and is sent
## home to an airfield BEHIND it asks for exactly that, every single time.
func test_a_course_reversal_actually_turns() -> void:
	var m: Movement = _flier(Movement.Mode.FLYING)
	m.turn_rate = 180.0
	var heading := Vector3(-1.0, 0.0, 0.0)
	var turned: Vector3 = m._turn_heading_toward(
		heading * 6.0, Vector3(1.0, 0.0, 0.0), deg_to_rad(6.0)
	)
	assert_almost_eq(turned.length(), 1.0, 0.001, "a direction comes back")
	assert_lt(
		turned.angle_to(heading), PI * 0.5, "it has begun turning away from where it was pointing"
	)
	assert_gt(
		turned.angle_to(heading), 0.0, "and it moved at all — the whole failure was that it did not"
	)


## Turning is still RATE LIMITED; the reversal fix must not become a snap.
func test_a_turn_is_capped_at_the_rate() -> void:
	var m: Movement = _flier(Movement.Mode.FLYING)
	var step: float = deg_to_rad(6.0)
	var turned: Vector3 = m._turn_heading_toward(
		Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), step
	)
	assert_almost_eq(
		turned.angle_to(Vector3(1.0, 0.0, 0.0)),
		step,
		0.0001,
		"a 90 degree demand yields exactly one tick of turn"
	)


## A demand already within reach is met outright rather than being eased into.
func test_a_small_turn_is_taken_whole() -> void:
	var m: Movement = _flier(Movement.Mode.FLYING)
	var want := Vector3(1.0, 0.0, 0.05)
	assert_eq(m._turn_heading_toward(Vector3(1.0, 0.0, 0.0), want, deg_to_rad(30.0)), want)
#endregion
