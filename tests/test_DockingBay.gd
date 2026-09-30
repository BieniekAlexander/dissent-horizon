extends GutTest

## Tests for the AIRFIELD half of the rearm mechanic: which aircraft a DockingBay admits,
## how its pads are claimed and released, and the capacity soft gate built on top.
##
## The ammunition model these serve is test_ChargedAmmo.gd. The two are deliberately
## separable — a bay recharges whatever a Loadout says is charged, and the ammo model does
## not know an airfield exists — so a later non-airfield resupply reuses one without the
## other.
##
## The flight itself (Rearm's approach → descend → taxi → dock → taxi → ascend sequence)
## is only partly covered here — the taxi steps below drive Rearm directly, but the flown
## half needs a live NavigationServer and a real Map, which this suite has no fixture for.
## `tools/rearm_probe.gd` is what exercises that end to end.

## Every piece is a fake (tests/_fake_pieces.gd): an airfield with pads and a runway, an
## aircraft with a charged clip that wants a pad, one that opts out, and a soldier.
const AIRFIELD: Dictionary = {"structure": true, "production": true, "docking_bay": {"pads": 3, "runways": 1}}
## A friendly aircraft with a CHARGED clip (it cannot reload in the field, so it wants a pad).
## A friendly aircraft with a CHARGED clip (it cannot reload in the field, so it wants a pad).
const CLIPPER: Dictionary = {"aerial": true, "docking": true, "vision": 8.0,
	"weapon": {"ground": 6.0, "clip_size": 4, "charged": true}}
const RECRUIT: Dictionary = FakePieces.SOLDIER
## An aircraft that opts out of airfields (Movement.docks) — expended on its first run, so
## there is nothing about a pad it could want. FLYING, so it passes every STRUCTURAL test
## for docking and is turned away purely on the flag.
const KAMIKAZE: Dictionary = {"aerial": true, "flying": true, "vision": 8.0}  # no Docking: it never wants a pad
func _commander(a_id: int) -> Commander:
	var c := Commander.new()
	c.id = a_id
	add_child_autofree(c)
	return c

## A live entity owned by `a_commander`. Ownership is assigned directly rather than through
## initialize() so no Map is needed — the same shortcut test_Garrison takes.
func _entity(a_options: Dictionary, a_commander: Commander) -> Commandable:
	var e := FakePieces.make(a_options) as Commandable
	add_child_autofree(e)
	e.ownership.commander = a_commander
	return e

## A FINISHED airfield. `is_built` is derived from build_progress, not settable, so a
## structure is finished by completing it — editor-placed structures already default to
## 1.0, and this is here to say so at the call site.
func _airfield(a_commander: Commander) -> Commandable:
	var f: Commandable = _entity(AIRFIELD, a_commander)
	f.build_progress = 1.0
	return f

#region Capacity comes from the pads
func test_capacity_is_the_pad_count() -> void:
	# Capacity is never a typed number: it is how many parking spaces the airfield's scene
	# carries, so the two can't disagree.
	var bay: DockingBay = _airfield(_commander(1)).docking_bay
	assert_not_null(bay, "the shipped airfield carries a DockingBay")
	assert_eq(bay.capacity(), bay.pads().size(), "capacity IS the pad count")
	assert_gt(bay.capacity(), 0, "and the shipped airfield has pads on it")

func test_a_fresh_bay_has_every_pad_free() -> void:
	var bay: DockingBay = _airfield(_commander(1)).docking_bay
	assert_eq(bay.free_pads().size(), bay.capacity(), "nothing is claimed yet")
	assert_true(bay.has_free_pad())
	assert_eq(bay.claimants().size(), 0)
#endregion

#region Who a bay admits
func test_a_bay_admits_a_friendly_aerial_unit() -> void:
	var cmd: Commander = _commander(1)
	var bay: DockingBay = _airfield(cmd).docking_bay
	assert_true(bay.admits(_entity(CLIPPER, cmd)), "a friendly helicopter docks")

func test_a_bay_refuses_a_ground_unit() -> void:
	# A runway is for aircraft. Asked of Movement.is_aerial_mode(), matching the axis
	# Garrison.occupiable_movements already uses for the same question.
	var cmd: Commander = _commander(1)
	var bay: DockingBay = _airfield(cmd).docking_bay
	assert_false(bay.admits(_entity(RECRUIT, cmd)), "infantry does not dock")

func test_a_bay_refuses_another_commander_s_aircraft() -> void:
	# Unlike a garrison, which also takes neutral hosts, an airfield is a service and
	# services are not shared.
	var bay: DockingBay = _airfield(_commander(1)).docking_bay
	assert_false(bay.admits(_entity(CLIPPER, _commander(2))), "an enemy aircraft is refused")

func test_a_bay_refuses_an_aircraft_that_opts_out_of_airfields() -> void:
	# The kamikaze is FLYING and friendly, so it clears every structural test; only its
	# having no Docking turns it away. Pinned here because declaring docking is what makes
	# that refusal declarative rather than incidental.
	var cmd: Commander = _commander(1)
	var bay: DockingBay = _airfield(cmd).docking_bay
	var drone: Commandable = _entity(KAMIKAZE, cmd)
	assert_eq(drone.movement.mode, Movement.Mode.FLYING, "it flies (the fixture this needs)")
	assert_false(bay.admits(drone), "but it does not use airfields")
	assert_null(bay.reserve(drone), "so it is handed no pad")

func test_an_unfinished_airfield_admits_nothing() -> void:
	var cmd: Commander = _commander(1)
	var field: Commandable = _entity(AIRFIELD, cmd)
	field.build_progress = 0.5
	assert_false(field.is_built, "half-built (the fixture this test needs)")
	assert_false(field.docking_bay.admits(_entity(CLIPPER, cmd)),
		"a half-built airfield has no deck to land on")
#endregion

#region Reserving and releasing pads
func test_reserving_claims_one_pad_and_is_idempotent() -> void:
	# Rearm re-reserves every tick while it approaches, so a second call must return the
	# same pad rather than eating the whole bay.
	var cmd: Commander = _commander(1)
	var bay: DockingBay = _airfield(cmd).docking_bay
	var plane: Commandable = _entity(CLIPPER, cmd)
	var pad: DockingPad = bay.reserve(plane)
	assert_not_null(pad, "a free bay hands out a pad")
	assert_eq(bay.free_pads().size(), bay.capacity() - 1, "exactly one pad is spoken for")
	assert_same(bay.reserve(plane), pad, "re-reserving returns the same pad")
	assert_eq(bay.free_pads().size(), bay.capacity() - 1, "and claims no second one")

func test_two_aircraft_get_different_pads() -> void:
	var cmd: Commander = _commander(1)
	var bay: DockingBay = _airfield(cmd).docking_bay
	var a: DockingPad = bay.reserve(_entity(CLIPPER, cmd))
	var b: DockingPad = bay.reserve(_entity(CLIPPER, cmd))
	assert_not_null(b)
	assert_ne(a, b, "no two aircraft converge on one space")

func test_a_full_bay_hands_out_nothing_but_still_admits() -> void:
	# admits / has_room / accepts, exactly as Garrison splits them: a full bay still ADMITS
	# a unit, which then waits for a pad rather than being refused the order.
	var cmd: Commander = _commander(1)
	var bay: DockingBay = _airfield(cmd).docking_bay
	for i in bay.capacity():
		assert_not_null(bay.reserve(_entity(CLIPPER, cmd)), "pad %d claimed" % i)
	var latecomer: Commandable = _entity(CLIPPER, cmd)
	assert_false(bay.has_free_pad(), "the bay is full")
	assert_null(bay.reserve(latecomer), "so nothing is handed out")
	assert_true(bay.admits(latecomer), "but the aircraft is still one this bay serves")
	assert_false(bay.accepts(latecomer), "it just cannot be taken right now")

func test_releasing_returns_the_pad() -> void:
	var cmd: Commander = _commander(1)
	var bay: DockingBay = _airfield(cmd).docking_bay
	var plane: Commandable = _entity(CLIPPER, cmd)
	bay.reserve(plane)
	bay.release(plane)
	assert_eq(bay.free_pads().size(), bay.capacity(), "the space is free again")

func test_a_stale_release_cannot_evict_the_current_occupant() -> void:
	# A Rearm torn down after its aircraft already left and another arrived must not throw
	# the newcomer off the pad.
	var cmd: Commander = _commander(1)
	var bay: DockingBay = _airfield(cmd).docking_bay
	var first: Commandable = _entity(CLIPPER, cmd)
	var pad: DockingPad = bay.reserve(first)
	pad.release(first)
	var second: Commandable = _entity(CLIPPER, cmd)
	pad.claim(second)
	pad.release(first)  # the stale release
	assert_same(pad.claimed_by(), second, "the current occupant keeps its pad")

func test_a_destroyed_claimant_does_not_strand_its_pad() -> void:
	# An aircraft shot down on final approach still holds a claim; a freed claimant must
	# read as gone rather than reserving a space forever.
	var cmd: Commander = _commander(1)
	var bay: DockingBay = _airfield(cmd).docking_bay
	var doomed: Commandable = _entity(CLIPPER, cmd)
	var pad: DockingPad = bay.reserve(doomed)
	assert_false(pad.is_free(), "claimed while alive")
	doomed.free()
	assert_true(pad.is_free(), "and free again once its claimant is gone")
	assert_null(pad.claimed_by(), "with no dangling reference reported")
#endregion

#region Recharging on the pad
func test_only_an_arrived_aircraft_is_recharged() -> void:
	# A pad is claimed from the moment its aircraft SETS OFF. Charging on the claim alone
	# would let a unit refill in flight and never actually land.
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	var plane: Commandable = _entity(CLIPPER, cmd)
	var weapon: Weapon = plane.weapon_inventory.get_weapons()[0]
	assert_true(weapon.charged, "the aircraft's weapon is charged (the fixture this needs)")
	for i in weapon.clip_size:
		weapon.consume_round()
	field.docking_bay.reserve(plane)
	for i in 60:
		field.docking_bay.tick_recharge()
	assert_eq(weapon.ammo(), 0, "an inbound aircraft takes on nothing")
	assert_false(plane.docking.is_docked_at(field.docking_bay.pads()[0]),
		"and does not count as docked merely for holding a pad")
#endregion

#region The capacity soft gate
func test_spare_capacity_counts_charged_aircraft_against_pads() -> void:
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	field.reparent(cmd)
	var pads: int = field.docking_bay.capacity()
	assert_eq(cmd.total_docking_capacity(), pads, "pads across every finished airfield")
	assert_true(cmd.has_spare_docking_capacity(), "empty commander, room to spare")
	for i in pads:
		_entity(CLIPPER, cmd).reparent(cmd)
	assert_eq(cmd.charged_aircraft_count(), pads, "every charged aircraft wants a pad")
	assert_false(cmd.has_spare_docking_capacity(), "and the gate closes at parity")

func test_units_that_reload_themselves_never_count_against_capacity() -> void:
	# The gate is about aircraft that MUST dock, not about aircraft. Infantry — and any
	# aircraft whose weapons reload in the field — are irrelevant to it.
	var cmd: Commander = _commander(1)
	_airfield(cmd).reparent(cmd)
	for i in 5:
		_entity(RECRUIT, cmd).reparent(cmd)
	assert_eq(cmd.charged_aircraft_count(), 0, "infantry does not want a pad")
	assert_true(cmd.has_spare_docking_capacity())

func test_opted_out_aircraft_do_not_consume_capacity() -> void:
	# A unit that can never occupy a pad must not reserve one in the arithmetic. Without
	# this a swarm of drones would report the air force as short of pads it does not need.
	var cmd: Commander = _commander(1)
	_airfield(cmd).reparent(cmd)
	for i in 10:
		_entity(KAMIKAZE, cmd).reparent(cmd)
	assert_eq(cmd.charged_aircraft_count(), 0, "drones want no pads")
	assert_true(cmd.has_spare_docking_capacity(), "so the gate stays open")

func test_an_opted_out_aircraft_is_sent_to_no_airfield() -> void:
	var cmd: Commander = _commander(1)
	_airfield(cmd).reparent(cmd)
	var drone: Commandable = _entity(KAMIKAZE, cmd)
	drone.reparent(cmd)
	assert_null(cmd.nearest_docking_bay_for(drone), "there is nowhere it would go")

func test_a_commander_with_no_airfield_has_no_capacity_and_no_bay_to_send_to() -> void:
	var cmd: Commander = _commander(1)
	var plane: Commandable = _entity(CLIPPER, cmd)
	plane.reparent(cmd)
	assert_eq(cmd.total_docking_capacity(), 0)
	assert_false(cmd.has_spare_docking_capacity(), "one aircraft, nowhere to put it")
	assert_null(cmd.nearest_docking_bay_for(plane), "and nowhere to send it")
#endregion

#region Choosing a bay
func test_the_nearest_bay_with_a_free_pad_wins() -> void:
	var cmd: Commander = _commander(1)
	var near: Commandable = _airfield(cmd)
	near.reparent(cmd)
	near.global_position = Vector3(5, 0, 0)
	var far: Commandable = _airfield(cmd)
	far.reparent(cmd)
	far.global_position = Vector3(50, 0, 0)
	var plane: Commandable = _entity(CLIPPER, cmd)
	plane.reparent(cmd)
	plane.global_position = Vector3.ZERO
	assert_same(cmd.nearest_docking_bay_for(plane), near.docking_bay, "the close one")

func test_a_full_near_bay_still_beats_no_bay_at_all() -> void:
	# With every pad taken the unit queues at the nearest rather than refusing to go —
	# the same "a full host is a queue, not a refusal" rule Occupy follows.
	var cmd: Commander = _commander(1)
	var only: Commandable = _airfield(cmd)
	only.reparent(cmd)
	var plane: Commandable = _entity(CLIPPER, cmd)
	plane.reparent(cmd)
	for i in only.docking_bay.capacity():
		only.docking_bay.reserve(_entity(CLIPPER, cmd))
	assert_false(only.docking_bay.has_free_pad(), "full")
	assert_same(cmd.nearest_docking_bay_for(plane), only.docking_bay,
		"still the one to head for")
#endregion


#region Runways
## A runway is a LINE with a takeoff point at one end, and the direction is the whole point
## of it: both halves of the choreography are stated relative to that end.
func _runway_of(a_field: Commandable) -> Runway:
	var bay: DockingBay = a_field.get_node("DockingBay") as DockingBay
	return bay.runway_for(bay.pads()[0])


func test_the_sky_port_authors_a_runway_along_its_apron() -> void:
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	var strip: Runway = _runway_of(field)
	assert_not_null(strip, "the Sky Port has a strip")
	assert_almost_eq(strip.heading().length(), 1.0, 0.001, "which points somewhere")
	assert_almost_eq(strip.takeoff_point().distance_to(strip.inner_point()), strip.length,
		0.01, "and runs its authored length from the threshold")


## Where a departing aircraft joins the strip, and where an arriving one leaves it.
func test_the_nearest_point_lands_on_the_strip_and_is_clamped_to_it() -> void:
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	var strip: Runway = _runway_of(field)
	var pad: DockingPad = (field.get_node("DockingBay") as DockingBay).pads()[0]

	var joined: Vector3 = strip.nearest_point(pad.dock_position())
	var along: float = (joined - strip.takeoff_point()).dot(strip.heading())
	assert_between(along, -0.01, strip.length + 0.01, "the join point is ON the strip")

	# Miles off either end still clamps onto the tarmac rather than running off it.
	var beyond: Vector3 = strip.takeoff_point() - strip.heading() * 500.0
	assert_almost_eq(strip.nearest_point(beyond).distance_to(strip.takeoff_point()), 0.0,
		0.01, "past the threshold clamps to the threshold")
	var past: Vector3 = strip.inner_point() + strip.heading() * 500.0
	assert_almost_eq(strip.nearest_point(past).distance_to(strip.inner_point()), 0.0,
		0.01, "and past the far end clamps to the far end")


## AN ARRIVAL MEETS THE TARMAC POINTING THE WAY A REAL ONE WOULD. The fix sits out beyond
## the threshold on the extended centreline, so the descent is flown ALONG the strip
## instead of dropping onto it across or back to front.
func test_the_approach_fix_lies_beyond_the_threshold_on_the_centreline() -> void:
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	var strip: Runway = _runway_of(field)
	var fix: Vector3 = strip.approach_point(10.0)

	assert_almost_eq(fix.distance_to(strip.takeoff_point()), 10.0, 0.01, "ten units out")
	var to_threshold: Vector3 = (strip.takeoff_point() - fix).normalized()
	assert_almost_eq(to_threshold.dot(strip.heading()), 1.0, 0.001,
		"and flying from it to the threshold means flying DOWN the runway")
	assert_gt(fix.distance_to(strip.inner_point()), strip.length,
		"so the fix is outside the field, not over the apron")
#endregion


#region Taxiing
## The ground drive is Movement's, shared by both halves so they cannot drift apart.
func test_taxiing_walks_the_aircraft_along_its_path_and_stops() -> void:
	var cmd: Commander = _commander(1)
	var plane: Commandable = _entity(CLIPPER, cmd)
	plane.global_position = Vector3(5.0, 0.0, 5.0)
	plane.aerial.park_on_deck(0.0)

	var arrived: Array[bool] = [false]
	plane.aerial.taxi_along(
		[Vector3(5.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.0)],
		func() -> void: arrived[0] = true)
	assert_true(plane.aerial.is_taxiing(), "rolling")
	assert_false(plane.aerial.is_docked(), "taxiing is not parked")

	for _i: int in 2000:
		if arrived[0]:
			break
		plane.aerial._physics_process(0.0)
	assert_true(arrived[0], "it reached the end of the path")
	assert_almost_eq(VU.inXZ(plane.global_position).length(), 0.0, 0.01,
		"parked exactly on the last waypoint, not near it")
	assert_true(plane.aerial.is_docked(), "and is back to being parked when it stops")


## A taxi is a ground drive, so the height is Commandable's business throughout.
func test_taxiing_leaves_the_height_alone() -> void:
	var cmd: Commander = _commander(1)
	var plane: Commandable = _entity(CLIPPER, cmd)
	plane.global_position = Vector3(5.0, 2.5, 0.0)
	plane.aerial.park_on_deck(0.0)
	plane.aerial.taxi_along([Vector3(0.0, 0.0, 0.0)], Callable())
	plane.aerial._physics_process(0.0)
	assert_almost_eq(plane.global_position.y, 2.5, 0.0001)


## Refused outright unless the unit is on a deck, so it can never be mistaken for a flight
## instruction.
func test_an_airborne_unit_cannot_be_told_to_taxi() -> void:
	var cmd: Commander = _commander(1)
	var plane: Commandable = _entity(CLIPPER, cmd)
	plane.aerial.taxi_along([Vector3(0.0, 0.0, 0.0)], Callable())
	assert_false(plane.aerial.is_taxiing())
#endregion


#region Rolling out onto a pad
## An airfield's own aircraft appears ON the airfield. Production asks the bay first and
## only falls back to the ordinary ground spawn when there is no pad for this unit.
func _production_of(a_field: Commandable) -> Production:
	return a_field.get_node("Production") as Production


func test_a_new_aircraft_is_rolled_out_onto_a_free_pad() -> void:
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	var plane: Commandable = _entity(CLIPPER, cmd)
	assert_true(_production_of(field)._spawn_on_pad(field, plane), "the bay took it")
	assert_true(plane.aerial.is_docked(), "and it is standing on the deck, not over it")
	assert_not_null(plane.docking.docked_pad, "holding the pad it was given")
	assert_eq(VU.inXZ(plane.global_position), VU.inXZ(plane.docking.docked_pad.dock_position()),
		"parked on the mark")


## The pad is HELD, so the next aircraft off the line gets a different one rather than
## being built on top of the first.
func test_two_aircraft_rolled_out_take_different_pads() -> void:
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	var a: Commandable = _entity(CLIPPER, cmd)
	var b: Commandable = _entity(CLIPPER, cmd)
	assert_true(_production_of(field)._spawn_on_pad(field, a))
	assert_true(_production_of(field)._spawn_on_pad(field, b))
	assert_ne(a.docking.docked_pad, b.docking.docked_pad)


## A unit the bay would not admit is spawned the ordinary way — a ground unit built at an
## airfield does not appear parked on the apron.
func test_a_ground_unit_is_never_rolled_out_onto_a_pad() -> void:
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	var soldier: Commandable = _entity(RECRUIT, cmd)
	assert_false(_production_of(field)._spawn_on_pad(field, soldier))
	assert_null(soldier.docking, "it does not dock, so it holds no pad")


## Leaving is the one way off, and it gives the space back.
func test_leaving_the_dock_returns_the_pad() -> void:
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	var bay: DockingBay = field.get_node("DockingBay") as DockingBay
	var plane: Commandable = _entity(CLIPPER, cmd)
	_production_of(field)._spawn_on_pad(field, plane)
	var pad: DockingPad = plane.docking.docked_pad
	assert_false(pad.is_free(), "held while it sits there")
	plane.docking.leave_dock()
	assert_true(pad.is_free(), "and handed back when it goes")
	assert_null(plane.docking.docked_pad)
	assert_eq(bay.free_pads().size(), bay.capacity())


## Calling it on a unit that was never docked must be harmless — CommandReceiver reaches
## for it on any drive.
func test_leaving_a_dock_you_are_not_in_does_nothing() -> void:
	var cmd: Commander = _commander(1)
	var plane: Commandable = _entity(CLIPPER, cmd)
	plane.docking.leave_dock()
	assert_null(plane.docking.docked_pad)
#endregion


#region Leaving by the runway
## An aircraft leaves its pad by ROLLING OUT, not by rising off the parking space. It joins
## the strip at the point nearest where it is parked, rolls along it to the threshold, and
## only climbs from there.
func test_leaving_a_pad_taxis_to_the_runway_before_climbing() -> void:
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	var bay: DockingBay = field.get_node("DockingBay") as DockingBay
	var plane: Commandable = _entity(CLIPPER, cmd)
	_production_of(field)._spawn_on_pad(field, plane)
	var strip: Runway = bay.runway_for(plane.docking.docked_pad)
	var started_at: Vector3 = plane.global_position

	plane.docking.leave_dock()
	assert_true(plane.aerial.is_taxiing(), "it rolls, it does not jump")
	assert_false(plane.aerial.is_airborne())
	assert_eq(plane.aerial._taxi_path.size(), 2,
		"two legs: across the apron onto the strip, then down it")
	assert_almost_eq(strip.distance_to(plane.aerial._taxi_path[0]), 0.0, 0.01,
		"the first leg ends ON the strip")
	assert_almost_eq(plane.aerial._taxi_path[1].distance_to(strip.takeoff_point()), 0.0,
		0.01, "and the second at the threshold it climbs from")
	assert_ne(started_at, plane.aerial._taxi_path[0],
		"the join is somewhere other than the pad, or there is no taxi at all")


## The pad goes back the moment it leaves, not when it finishes taxiing — otherwise a space
## stays blocked while its occupant is already halfway down the runway.
func test_the_pad_is_released_as_soon_as_it_rolls() -> void:
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	var plane: Commandable = _entity(CLIPPER, cmd)
	_production_of(field)._spawn_on_pad(field, plane)
	var pad: DockingPad = plane.docking.docked_pad
	plane.docking.leave_dock()
	assert_true(pad.is_free())
	assert_null(plane.docking.docked_pad)


## A bay with no runway keeps the old behaviour: straight up off the pad. That is the path
## every airfield took before runways existed, and the one a HOVERING dock would want —
## a helicopter has no roll-out to fly.
func test_a_bay_with_no_runway_still_lifts_straight_off_the_pad() -> void:
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	var bay: DockingBay = field.get_node("DockingBay") as DockingBay
	for strip: Runway in bay.runways():
		strip.free()
	var plane: Commandable = _entity(CLIPPER, cmd)
	_production_of(field)._spawn_on_pad(field, plane)
	plane.docking.leave_dock()
	assert_false(plane.aerial.is_taxiing(), "nothing to roll along")
	assert_false(plane.aerial.is_docked(), "but it did leave")
#endregion


#region No pad, no aircraft
## An aircraft that rearms is rolled out ONTO a pad and holds it, so an airfield whose every
## pad is spoken for has literally nowhere to put another one.
## A train button for a piece that does (or does not) take a pad. Built here, not read from the
## registry: which shipped pieces rearm is content.
func _tool_for(a_needs_docking: bool) -> Tool:
	var tool := Tool.new("command_tool_fake", &"fake_unit", null, "fake", Vector2i.ZERO, 0, 0)
	tool.needs_docking = a_needs_docking
	return tool


func test_training_is_refused_once_every_pad_is_taken() -> void:
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	var bay: DockingBay = field.get_node("DockingBay") as DockingBay
	var docker: Tool = _tool_for(true)

	assert_true(Train.has_free_pad_for(field, docker), "an empty airfield can build one")
	for pad: DockingPad in bay.pads():
		pad.claim(_entity(CLIPPER, cmd))
	assert_false(bay.has_free_pad(), "every space is now spoken for")
	assert_false(Train.has_free_pad_for(field, docker), "so there is nowhere to put another")


## The rule is about pieces that OCCUPY a pad. Everything else is none of its business.
func test_a_piece_that_never_docks_is_never_blocked() -> void:
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	for pad: DockingPad in (field.get_node("DockingBay") as DockingBay).pads():
		pad.claim(_entity(CLIPPER, cmd))
	var ground: Tool = _tool_for(false)
	assert_true(Train.has_free_pad_for(field, ground))


## A producer with no bay at all cannot be short of pads.
func test_a_producer_with_no_bay_is_never_blocked() -> void:
	var cmd: Commander = _commander(1)
	var barracks: Commandable = _entity({"structure": true}, cmd)
	assert_null(barracks.get_node_or_null("DockingBay"))
	assert_true(Train.has_free_pad_for(barracks, _tool_for(true)))
#endregion


#region One aircraft per strip
## A runway is held whole. Two aircraft rolling down the same strip would drive through
## each other, and the taxi is a scripted drive along an authored line — the line settles
## the question, so nothing has to ask the physics engine.
func test_a_runway_is_held_by_one_unit_at_a_time() -> void:
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	var strip: Runway = _runway_of(field)
	var a: Commandable = _entity(CLIPPER, cmd)
	var b: Commandable = _entity(CLIPPER, cmd)

	assert_true(strip.is_free())
	assert_true(strip.claim(a), "first one takes it")
	assert_false(strip.claim(b), "second one is turned away")
	assert_eq(strip.claimed_by(), a)

	strip.release(b)
	assert_eq(strip.claimed_by(), a, "a stale release cannot evict the holder")
	strip.release(a)
	assert_true(strip.is_free(), "and the holder gives it back")
	assert_true(strip.claim(b), "so the next one can have it")


## A claim cannot outlive its claimant and strand the strip for the rest of the match.
func test_a_runway_frees_itself_when_its_claimant_dies() -> void:
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	var strip: Runway = _runway_of(field)
	var doomed: Commandable = _entity(CLIPPER, cmd)
	strip.claim(doomed)
	doomed.free()
	assert_true(strip.is_free())


## A busy strip is a WAIT, not a refusal: the aircraft keeps its pad and tries again.
func test_a_busy_runway_keeps_the_departing_aircraft_on_its_pad() -> void:
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	var bay: DockingBay = field.get_node("DockingBay") as DockingBay
	var strip: Runway = _runway_of(field)
	var blocker: Commandable = _entity(CLIPPER, cmd)
	strip.claim(blocker)

	var waiting: Commandable = _entity(CLIPPER, cmd)
	_production_of(field)._spawn_on_pad(field, waiting)
	var pad: DockingPad = waiting.docking.docked_pad
	waiting.docking.leave_dock()
	assert_true(waiting.aerial.is_docked(), "it stayed put")
	assert_false(waiting.aerial.is_taxiing())
	assert_eq(waiting.docking.docked_pad, pad, "and kept its space rather than giving it up")
	assert_false(pad.is_free())

	strip.release(blocker)
	waiting.docking.leave_dock()
	assert_true(waiting.aerial.is_taxiing(), "and rolls the moment the strip is clear")
	assert_eq(strip.claimed_by(), waiting)
#endregion


#region Turning and rolling are separate
## On the ground an aircraft is a vehicle with a nosewheel: it stops, swings the nose round
## to point at where it is going, and only then drives. Doing both at once slid it
## diagonally across the apron, which is the one thing an aeroplane cannot do.
func test_a_taxiing_unit_turns_before_it_moves() -> void:
	var cmd: Commander = _commander(1)
	var plane: Commandable = _entity(CLIPPER, cmd)
	plane.global_position = Vector3.ZERO
	plane.movement.turn_rate = 90.0
	plane.aerial.park_on_deck(0.0)
	# Straight behind it, so it must turn all the way round before it may roll.
	plane.movement.face_toward(Vector3(0.0, 0.0, 10.0))
	plane.aerial.taxi_along([Vector3(0.0, 0.0, -10.0)], Callable())

	plane.aerial._physics_process(0.0)
	assert_almost_eq(plane.global_position.length(), 0.0, 0.001,
		"it has not moved a millimetre while it is still swinging round")

	for _i: int in 400:
		plane.aerial._physics_process(0.0)
		if plane.global_position.length() > 0.01:
			break
	assert_gt(plane.global_position.length(), 0.01, "and once pointed, it rolls")
	assert_true(plane.movement.is_facing_within(Vector3(0.0, 0.0, -10.0), 0.05),
		"pointed the way it is going, not crabbing sideways")
#endregion


#region Waiting for the strip keeps the order
## ORDERING A WHOLE FLIGHT OFF ONE STRIP. Only the first can roll; the rest have to keep
## their orders and wait their turn. They used to lose them outright: a parked unit reports
## is_navigation_finished() (anything GROUNDED_TEMP does), so the receiver's arrival branch
## read a unit that had not moved an inch as having reached its destination and threw the
## order away.
func test_an_aircraft_waiting_for_the_runway_keeps_its_order() -> void:
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	var strip: Runway = _runway_of(field)
	strip.claim(_entity(CLIPPER, cmd))          # somebody else has the strip

	var waiting: Commandable = _entity(CLIPPER, cmd)
	_production_of(field)._spawn_on_pad(field, waiting)
	waiting.update_commands(MoveCommand.new(
		CommandMessage.new(null, null, null, Vector3(40.0, 0.0, 40.0))))
	assert_false(waiting.command_receiver.is_idle(), "it took the order")

	for _i: int in 30:
		waiting.command_receiver._process_commands()
	assert_false(waiting.command_receiver.is_idle(),
		"and still has it after thirty ticks of being unable to roll")
	assert_true(waiting.aerial.is_docked(), "because it never left its pad")


## The strip goes back the moment its user is airborne, so the next one can have it.
func test_the_strip_is_released_once_the_departing_aircraft_is_airborne() -> void:
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	var strip: Runway = _runway_of(field)
	var plane: Commandable = _entity(CLIPPER, cmd)
	_production_of(field)._spawn_on_pad(field, plane)

	plane.docking.leave_dock()
	assert_eq(strip.claimed_by(), plane, "held while it rolls")
	plane.docking.release_runway()
	assert_eq(strip.claimed_by(), plane, "and still held while it is climbing out")

	plane.aerial.park_on_deck(0.0)
	plane.aerial.take_off()
	for _i: int in 2000:
		plane.aerial._physics_process(0.0)
		if plane.aerial.is_airborne():
			break
	plane.docking.release_runway()
	assert_true(strip.is_free(), "and handed back the moment it is airborne")
#endregion


#region Interrupting a rearm on the pad
## A live Rearm with its pad already claimed, as the first tick of one would leave it.
func _rearm_on(a_actor: Commandable, a_field: Commandable) -> Rearm:
	var order := Rearm.new(CommandMessage.new(null, a_field, null, a_field.global_position))
	order.get_updated_state(a_actor)   # claims a pad
	return order


## A REARM CUT SHORT LEAVES THE AIRCRAFT WHERE IT IS, holding its pad. Whatever order
## replaced the rearm then takes it off through leave_dock, which TAXIS.
##
## Lifting it here instead is what made a part-charged aircraft rise vertically off its
## parking space and skip the runway entirely, while a fully-charged one — whose rearm had
## COMPLETED, so this path never ran — taxied out correctly. That difference is exactly the
## "only when they do not have full charges" symptom.
func test_a_rearm_cut_short_hands_the_pad_over_instead_of_taking_off() -> void:
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	var plane: Commandable = _entity(CLIPPER, cmd)
	var order: Rearm = _rearm_on(plane, field)
	var pad: DockingPad = order._pad
	# Park it exactly as a completed descent would, mid-recharge.
	plane.global_position = pad.dock_position()
	plane.aerial.park_on_deck(pad.deck_height)

	order.on_released(plane)
	assert_true(plane.aerial.is_docked(), "it is still standing on the deck")
	assert_eq(plane.docking.docked_pad, pad, "and now owns the pad itself — the command let go of it")
	assert_null(order._pad, "so the command no longer holds it")
	assert_true(plane.docking.is_docked_on_pad(), "so its departure will go through leave_dock")


## Interrupted in the AIR, though, it must still be lifted — nothing else knows to.
func test_a_rearm_cut_short_in_the_air_still_takes_off() -> void:
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	var plane: Commandable = _entity(CLIPPER, cmd)
	var order: Rearm = _rearm_on(plane, field)
	order.on_released(plane)
	assert_null(plane.docking.docked_pad, "nothing to hand over — it never parked")
	assert_true(order._pad == null or order._pad.is_free(), "and the pad went back")
#endregion


#region Pointing the right way, and opening up
## Time spent turning on the spot is time the aircraft is not moving, so a parked one with
## nothing to do points itself at the taxiway.
func test_a_parked_idle_aircraft_turns_toward_its_taxiway() -> void:
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	var strip: Runway = _runway_of(field)
	var plane: Commandable = _entity(CLIPPER, cmd)
	_production_of(field)._spawn_on_pad(field, plane)
	var join: Vector3 = strip.nearest_point(plane.global_position)
	plane.movement.face_toward(plane.global_position - (join - plane.global_position))

	for _i: int in 400:
		plane.docking.aim_parked_at_runway()
	assert_true(plane.movement.is_facing_within(
		Vector3(join.x, plane.global_position.y, join.z), 0.05),
		"it has come round to face the way it will leave")


## The apron is a crawl; the strip is a takeoff roll. An aircraft that trundled to the
## threshold at taxi speed and then jumped into the air is not taking off.
func test_the_last_leg_of_a_departure_opens_up_to_flight_speed() -> void:
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	var plane: Commandable = _entity(CLIPPER, cmd)
	_production_of(field)._spawn_on_pad(field, plane)
	plane.docking.leave_dock()
	assert_true(plane.aerial.is_taxiing())

	var fastest: float = 0.0
	for _i: int in 4000:
		plane.aerial._physics_process(0.0)
		fastest = maxf(fastest, VU.inXZ(plane.movement._current_velocity).length())
		if not plane.aerial.is_taxiing():
			break
	assert_gt(fastest, plane.movement.speed * Aerial.TAXI_SPEED_FACTOR + 0.5,
		"it went faster than a taxi somewhere along the way")
	assert_almost_eq(fastest, plane.movement.speed, plane.movement.speed * 0.35,
		"and got near flight speed by the threshold")
#endregion


#region Established on final
## An aircraft may only start down when it is POINTED DOWN THE STRIP. The test used to be
## distance to the approach fix alone, so one arriving from the far side flew through the
## fix at cruise heading directly AWAY from the runway and committed anyway — and the
## descent then had to turn it 180 degrees while it sank, which is the wide repeated
## swinging that looks like an aircraft unable to find the field.
func _approaching(a_field: Commandable, a_plane: Commandable) -> Rearm:
	var order := Rearm.new(CommandMessage.new(null, a_field, null, a_field.global_position))
	order.get_updated_state(a_plane)
	return order


func _place_on_final(a_plane: Commandable, a_strip: Runway, a_out: float,
		a_lateral: float, a_reversed: bool) -> void:
	var along: Vector3 = a_strip.heading()
	var side := Vector3(-along.z, 0.0, along.x)
	a_plane.global_position = a_strip.takeoff_point() - along * a_out + side * a_lateral
	var aim: Vector3 = a_plane.global_position + (-along if a_reversed else along)
	for _i: int in 600:
		if a_plane.movement.is_facing(aim):
			break
		a_plane.movement.face_toward(aim)


func test_an_aircraft_pointed_down_the_strip_may_start_down() -> void:
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	var strip: Runway = _runway_of(field)
	var plane: Commandable = _entity(CLIPPER, cmd)
	var order: Rearm = _approaching(field, plane)
	_place_on_final(plane, strip, 4.0, 0.0, false)
	assert_true(order._is_established_on_final(plane))


## Flying the other way is the case that used to slip through.
func test_an_aircraft_pointed_away_may_not() -> void:
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	var strip: Runway = _runway_of(field)
	var plane: Commandable = _entity(CLIPPER, cmd)
	var order: Rearm = _approaching(field, plane)
	_place_on_final(plane, strip, 4.0, 0.0, true)
	assert_false(order._is_established_on_final(plane),
		"sitting on the centreline is not enough if it is heading out of the field")


## Nor from the wrong side of the threshold — it is past the numbers.
func test_an_aircraft_beyond_the_threshold_may_not() -> void:
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	var strip: Runway = _runway_of(field)
	var plane: Commandable = _entity(CLIPPER, cmd)
	var order: Rearm = _approaching(field, plane)
	_place_on_final(plane, strip, -3.0, 0.0, false)
	assert_false(order._is_established_on_final(plane))


## THE CORRIDOR HAS TO ADMIT A TURN DIAMETER. An aircraft that has just come round 180
## degrees rolls out that far off the line it started on; a corridor narrower than that is
## one no aircraft arriving from the far side can ever satisfy, so it circles forever.
func test_the_corridor_admits_an_aircraft_that_has_just_turned_around() -> void:
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	var strip: Runway = _runway_of(field)
	var plane: Commandable = _entity(CLIPPER, cmd)
	var order: Rearm = _approaching(field, plane)
	var diameter: float = plane.movement.turn_radius() * 2.0
	assert_gt(diameter, 0.0, "the clipper has a finite turn rate")
	_place_on_final(plane, strip, 4.0, diameter * 0.9, false)
	assert_true(order._is_established_on_final(plane),
		"a turn-diameter offset is a correction the descent can converge, not a rejection")


## Miles off to the side is still a rejection, though.
func test_far_off_the_centreline_is_still_refused() -> void:
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	var strip: Runway = _runway_of(field)
	var plane: Commandable = _entity(CLIPPER, cmd)
	var order: Rearm = _approaching(field, plane)
	_place_on_final(plane, strip, 4.0, 40.0, false)
	assert_false(order._is_established_on_final(plane))
#endregion


#region The pad is the unit's from touchdown
## Everything that asks "is this aircraft standing on a pad" goes through
## Commandable.docking.docked_pad — releasing the runway, turning to face the taxiway, leaving
## through leave_dock. Holding it on the COMMAND until the clip was full meant an aircraft
## spent its whole refuelling stop still owning the runway and still pointing the way it
## landed.
func test_reaching_the_pad_hands_it_over_and_frees_the_strip() -> void:
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	var strip: Runway = _runway_of(field)
	var plane: Commandable = _entity(CLIPPER, cmd)
	var order: Rearm = _approaching(field, plane)
	var pad: DockingPad = order._pad
	strip.claim(plane)
	plane.docking.claimed_runway = strip
	plane.global_position = pad.dock_position()
	plane.aerial.park_on_deck(pad.deck_height)

	order._park(plane)
	assert_eq(order.state, Rearm.DockState.DOCKED)
	assert_eq(plane.docking.docked_pad, pad, "the unit owns its space from touchdown")
	assert_null(order._pad, "and the command has let go of it")

	plane.docking.release_runway()
	assert_true(strip.is_free(), "so the strip goes back at once, not after the reload")


## And it turns to face its taxiway straight away, rather than after the reload.
func test_a_refuelling_aircraft_already_faces_its_taxiway() -> void:
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	var strip: Runway = _runway_of(field)
	var plane: Commandable = _entity(CLIPPER, cmd)
	var order: Rearm = _approaching(field, plane)
	var pad: DockingPad = order._pad
	plane.global_position = pad.dock_position()
	plane.aerial.park_on_deck(pad.deck_height)
	order._park(plane)
	# Still mid-recharge: a live command, not idle.
	plane.update_commands(order)

	var join: Vector3 = strip.nearest_point(plane.global_position)
	for _i: int in 600:
		plane.docking.aim_parked_at_runway()
	assert_true(plane.movement.is_facing_within(
		Vector3(join.x, plane.global_position.y, join.z), 0.05),
		"pointed the way it will leave while it is still taking on fuel")
#endregion


#region Losing the deck under you
## An airfield destroyed with aircraft parked on it. The pads go with it, so the claim a
## unit is holding becomes a freed reference — which is not the same as no claim, and the
## difference used to be fatal: the whole approach/park sequence is driven off a typed
## `Entity` target, and Godot type-checks an Object argument BEFORE the callee's own
## is_instance_valid guard can run.
##
## The rule (see gdd/systems/combat/aerial-operations/docking-bays-and-pads.md): give up the
## space that no longer exists, then go and stand somewhere else — or hold over the wreck
## when there is nowhere else to stand.

## Kill `a_field` outright and let the frees settle, so its pads are genuinely gone.
func _demolish(a_field: Commandable) -> void:
	a_field.get_parent().remove_child(a_field)
	a_field.free()


func test_the_lost_pad_is_given_up_and_the_aircraft_lifts_off() -> void:
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	var plane: Commandable = _entity(CLIPPER, cmd)
	_production_of(field)._spawn_on_pad(field, plane)
	assert_true(plane.aerial.is_docked(), "guards the fixture")

	_demolish(field)
	plane.docking.release_lost_dock()

	assert_false(plane.aerial.is_docked(), "it is not standing on anything any more")
	assert_false(is_instance_valid(plane.docking.docked_pad), "and holds no pad")


func test_a_parked_aircraft_with_a_live_pad_is_left_alone() -> void:
	# The same check runs every tick on every parked aircraft, so it must be inert for the
	# ordinary case — including the window between touching down and being handed the pad.
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	var plane: Commandable = _entity(CLIPPER, cmd)
	_production_of(field)._spawn_on_pad(field, plane)

	plane.docking.release_lost_dock()

	assert_true(plane.aerial.is_docked(), "still parked")
	assert_eq(plane.docking.docked_pad.claimed_by(), plane, "and still holding its space")


func test_an_inbound_aircraft_holding_a_reserved_pad_is_left_alone() -> void:
	# docked_pad is null for the whole descent and taxi — the Rearm holds the reservation —
	# so "no docked_pad" alone must not read as "my airfield was destroyed".
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	var bay: DockingBay = field.get_node("DockingBay") as DockingBay
	var plane: Commandable = _entity(CLIPPER, cmd)
	plane.aerial.park_on_deck(0.0)
	assert_not_null(bay.reserve(plane), "the bay gave it a space")
	assert_null(plane.docking.docked_pad, "which it has not been handed yet")

	plane.docking.release_lost_dock()

	assert_true(plane.aerial.is_docked(), "so it stays where it is")


func test_the_aircraft_is_sent_to_another_airfield_when_one_exists() -> void:
	var cmd: Commander = _commander(1)
	var doomed: Commandable = _airfield(cmd)
	var refuge: Commandable = _airfield(cmd)
	var plane: Commandable = _entity(CLIPPER, cmd)
	_production_of(doomed)._spawn_on_pad(doomed, plane)

	_demolish(doomed)
	plane.docking.release_lost_dock()

	var rearm := plane.current_command() as Rearm
	assert_not_null(rearm, "it is reassigned rather than left circling")
	assert_eq(rearm.message.target, refuge, "to the airfield that is still standing")


func test_with_nowhere_left_to_go_it_holds_over_the_wreck() -> void:
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	var plane: Commandable = _entity(CLIPPER, cmd)
	_production_of(field)._spawn_on_pad(field, plane)
	var parked_at: Vector3 = plane.global_position

	_demolish(field)
	plane.docking.release_lost_dock()

	assert_null(plane.current_command(), "no airfield to be sent to")
	assert_eq(VU.inXZ(plane.aerial._anchor), VU.inXZ(parked_at),
		"so it orbits where its airfield used to be")


func test_a_rearm_whose_airfield_dies_ends_instead_of_crashing() -> void:
	# The crash itself: Rearm._bay_of took a typed Entity, so the freed airfield failed the
	# ARGUMENT type-check and the is_instance_valid guard one line inside never ran.
	var cmd: Commander = _commander(1)
	var field: Commandable = _airfield(cmd)
	var plane: Commandable = _entity(CLIPPER, cmd)
	var order := Rearm.new(CommandMessage.new(null, field, null, field.global_position))
	_demolish(field)
	assert_null(order.get_updated_state(plane), "the order ends, quietly")
#endregion
