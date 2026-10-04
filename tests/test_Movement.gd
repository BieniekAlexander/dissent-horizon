extends GutTest

## Tests for the Movement component.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_Movement.gd
##
## A live NavigationAgent3D depends on the NavigationServer being warmed up
## (a map, region, baked navmesh), which is far more setup than a unit test
## should pull in. These tests cover the contract Movement exposes:
##   - safe defaults when no nav agent is wired
##   - the nav_agent_path resolves a sibling correctly
##   - velocity_ready forwards from the agent's velocity_computed
##   - set_avoidance_team writes both layers and mask


## The Aerial a flying test Movement sits beside.
func _air(a_m: Movement) -> Aerial:
	return a_m.get_parent().get_node("Aerial") as Aerial


## Give `a_parent` an Aerial in `a_mode`. Added BEFORE the parent's Movement, which settles
## whether it flies the first time it is asked once it is in the tree.
func _add_aerial(a_parent: Node, a_mode: Movement.Mode) -> Aerial:
	var aerial := Aerial.new()
	aerial.name = "Aerial"
	aerial.mode = a_mode
	a_parent.add_child(aerial)
	return aerial


func _make_movement_without_agent() -> Movement:
	var m := Movement.new()
	add_child_autofree(m)
	return m


func test_default_target_position_is_zero_without_agent():
	var m := _make_movement_without_agent()
	assert_eq(m.target_position, Vector3.ZERO)


func test_set_target_position_is_safe_without_agent():
	# Should not crash — the component is designed to no-op when the agent
	# isn't wired (e.g., a Movement was added to a scene without a nav agent).
	var m := _make_movement_without_agent()
	m.set_target_position(Vector3(1, 0, 1))
	# target_position still reads as ZERO because there's no agent backing it.
	assert_eq(m.target_position, Vector3.ZERO)


func test_is_navigation_finished_defaults_to_true_without_agent():
	# Without an agent, "navigation is done" is the safe interpretation —
	# this prevents callers from spinning on an entity that can't move.
	var m := _make_movement_without_agent()
	assert_true(m.is_navigation_finished())


func test_get_next_path_position_defaults_to_zero_without_agent():
	var m := _make_movement_without_agent()
	assert_eq(m.get_next_path_position(), Vector3.ZERO)


func test_nav_agent_path_resolves_on_ready():
	# Wire a real NavigationAgent3D sibling so we can verify the Movement
	# component finds it via the exported NodePath. We don't activate the
	# nav server, so we only verify the reference plumbing, not pathfinding.
	var parent := Node3D.new()
	add_child_autofree(parent)
	var agent := NavigationAgent3D.new()
	agent.name = "NavigationAgent"
	parent.add_child(agent)
	var m := Movement.new()
	m.nav_agent_path = NodePath("../NavigationAgent")
	parent.add_child(m)  # triggers _ready, resolves the path
	# After _ready, set_target_position should reach the real agent.
	m.set_target_position(Vector3(5, 0, 5))
	# Read it back via the property — confirms _nav_agent is wired up.
	assert_eq(m.target_position, Vector3(5, 0, 5))


func test_enable_avoidance_configures_layers_and_mask():
	var parent := Node3D.new()
	add_child_autofree(parent)
	var agent := AvoidanceAgent3D.new()
	agent.name = "NavigationAgent"
	parent.add_child(agent)
	var m := Movement.new()
	m.nav_agent_path = NodePath("../NavigationAgent")
	parent.add_child(m)
	m.enable_avoidance(2)  # commander id 2 -> team bit 1<<2
	assert_eq(agent.avoidance_layers, AvoidanceAgent3D.team_bit(2), "broadcasts on its team bit")
	# Cross-team avoidance is now one-sided via NavigationObstacle3D, so the mask is
	# own team bit (same-team reciprocal RVO) + every FOREIGN obstacle bit + the
	# exception pool — NOT a blanket avoid-all. See AvoidanceAgent3D._current_mask.
	var mask := agent.avoidance_mask
	assert_ne(
		mask & AvoidanceAgent3D.team_bit(2), 0, "masks own team bit (same-team reciprocal RVO)"
	)
	assert_ne(
		mask & AvoidanceAgent3D.obstacle_bit(1), 0, "masks a foreign commander's obstacle bit"
	)
	assert_eq(mask & AvoidanceAgent3D.obstacle_bit(2), 0, "does NOT mask its own obstacle bit")


func test_velocity_ready_forwards_from_agent_velocity_computed():
	var parent := Node3D.new()
	add_child_autofree(parent)
	var agent := NavigationAgent3D.new()
	agent.name = "NavigationAgent"
	parent.add_child(agent)
	var m := Movement.new()
	m.nav_agent_path = NodePath("../NavigationAgent")
	parent.add_child(m)
	watch_signals(m)
	# Manually emit on the underlying agent — the Movement component should
	# forward via its own velocity_ready signal.
	agent.velocity_computed.emit(Vector3(2, 0, 0))
	assert_signal_emitted_with_parameters(m, "velocity_ready", [Vector3(2, 0, 0)])


#region FLYING dive-attack
## Helper: a FLYING Movement under a Node3D parent at `pos`, _ready'd (so its height
## offset is seeded to AERIAL_HEIGHT).
func _make_flying(a_pos: Vector3) -> Movement:
	var parent := Node3D.new()
	add_child_autofree(parent)
	parent.global_position = a_pos
	var m := Movement.new()
	m.name = "Locomotion"
	_add_aerial(parent, Movement.Mode.FLYING)
	parent.add_child(m)  # triggers _ready
	return m


func test_flying_starts_at_cruise_altitude():
	var m := _make_flying(Vector3(10, 0, 10))
	assert_almost_eq(_air(m).height_offset(), Aerial.AERIAL_HEIGHT, 0.001)


## Fly `m`'s parent toward `target_xz` at `speed` (world-units/s), requesting a dive every
## tick, until it arrives or `max_ticks` elapse. Returns the height offset on arrival.
##
## This is the case the old flat-rate descent could not do: the dive has to shed the whole
## cruise altitude within the seconds the horizontal run actually takes.
func _fly_dive_run(
	a_m: Movement, a_target_xz: Vector2, a_speed: float, a_max_ticks: int = 600
) -> float:
	var parent := a_m.get_parent() as Node3D
	var tps: float = float(TimeUtils.ticks_per_second())
	for i in a_max_ticks:
		var here: Vector2 = VU.in_xz(parent.global_position)
		var to_target: Vector2 = a_target_xz - here
		if to_target.length() <= a_speed / tps:
			parent.global_position = Vector3(a_target_xz.x, parent.global_position.y, a_target_xz.y)
			a_m._current_velocity = Vector3.ZERO
			_air(a_m).request_dive(a_target_xz)
			_air(a_m)._update_flying_height()
			return _air(a_m).height_offset()
		var step: Vector2 = to_target.normalized() * (a_speed / tps)
		parent.global_position += Vector3(step.x, 0.0, step.y)
		a_m._current_velocity = (
			Vector3(to_target.normalized().x, 0.0, to_target.normalized().y) * a_speed
		)
		_air(a_m).request_dive(a_target_xz)
		_air(a_m)._update_flying_height()
	return _air(a_m).height_offset()


func test_flying_dive_reaches_the_target_altitude_on_arrival():
	# The headline fix. A kamikaze crossing its 3-unit dive window at speed 4 has 0.75s to
	# shed 6 units of altitude; the old flat 1.5 u/s descent bought only ~1.1 of them, so it
	# arrived over its victim still ~5 units up and detonated there.
	var m := _make_flying(Vector3(0, 0, 0))
	var target := Vector2(20.0, 0.0)
	var offset_on_arrival: float = _fly_dive_run(m, target, 4.0)
	assert_lt(
		offset_on_arrival,
		0.5,
		"the drone is level with its target when it gets there, not still at altitude"
	)


func test_flying_dive_reaches_the_target_across_a_range_of_speeds():
	# The descent is derived from the closing speed, so it must hold up whether the unit
	# creeps in or comes in fast — not just at one tuned speed.
	for speed: float in [2.0, 4.0, 8.0]:
		var m := _make_flying(Vector3(0, 0, 0))
		var offset: float = _fly_dive_run(m, Vector2(20.0, 0.0), speed)
		assert_lt(offset, 0.5, "dive arrives on target at speed %.1f" % speed)


func test_flying_holds_cruise_altitude_until_it_commits():
	# Outside dive_distance the unit must stay up: descending the whole way in would drag it
	# along the deck across the entire approach.
	var m := _make_flying(Vector3(0, 0, 0))
	var parent := m.get_parent() as Node3D
	var target := Vector2(40.0, 0.0)
	# Fly to a point comfortably outside the commit window and check it is still at cruise.
	var stop_at: float = 40.0 - (_air(m)._dive_commit_distance(4.0) + 2.0)
	var tps: float = float(TimeUtils.ticks_per_second())
	while parent.global_position.x < stop_at:
		parent.global_position.x += 4.0 / tps
		m._current_velocity = Vector3(4.0, 0, 0)
		_air(m).request_dive(target)
		_air(m)._update_flying_height()
	assert_almost_eq(
		_air(m).height_offset(),
		Aerial.AERIAL_HEIGHT,
		0.01,
		"still at cruise altitude outside the commit window"
	)


func test_terminal_guidance_sharpens_the_turn_only_while_diving():
	# A ramming run is geometrically impossible at cruise handling: minimum turn radius is
	# speed / turn_rate, which for the kamikaze (4.0 / 120 deg/s) is 1.9 units against a
	# 0.5-unit reach — it would orbit its target forever. The dive boost closes that.
	var m := _make_flying(Vector3.ZERO)
	m.turn_rate = 120.0
	_air(m).dive_turn_rate_multiplier = 4.0
	assert_almost_eq(m._effective_turn_rate(), 120.0, 0.001, "cruise handling by default")
	_air(m)._dive_committed = true
	assert_almost_eq(m._effective_turn_rate(), 480.0, 0.001, "and terminal guidance on the run in")
	var radius: float = m.speed / deg_to_rad(m._effective_turn_rate())
	assert_lt(radius, 1.0, "the boosted turn radius is tight enough to actually connect")


func test_terminal_guidance_leaves_instant_turners_alone():
	var m := _make_flying(Vector3.ZERO)
	m.turn_rate = INF
	_air(m)._dive_committed = true
	assert_eq(m._effective_turn_rate(), INF, "an already-instant turn cannot be sharpened")


func test_dive_commit_distance_scales_with_speed():
	# The authored dive_distance is a floor; a faster unit has to nose over sooner because
	# the descent takes the same seconds either way.
	var m := _make_flying(Vector3(0, 0, 0))
	assert_almost_eq(
		_air(m)._dive_commit_distance(0.0),
		_air(m).dive_distance,
		0.001,
		"a stationary unit commits at the authored range"
	)
	assert_gt(
		_air(m)._dive_commit_distance(8.0),
		_air(m)._dive_commit_distance(4.0),
		"a faster unit commits earlier"
	)


## Ticks to fully descend/ascend the cruise altitude at LANDING_SPEED, with headroom —
## derived from the constants so the tests hold if AERIAL_HEIGHT changes. LANDING_SPEED is
## world-units per SECOND, so convert to a per-tick step first; the FLYING dive path this
## budgets for (_update_flying_height) moves at that flat rate.
func _full_height_ticks() -> int:
	var per_tick: float = Aerial.LANDING_SPEED / float(TimeUtils.ticks_per_second())
	return int(ceil(Aerial.AERIAL_HEIGHT / per_tick)) + 20


func test_flying_dive_onto_target_reaches_ground():
	# Diving straight onto the target's XZ (distance 0) drops to ~ground level.
	var m := _make_flying(Vector3(10, 0, 10))
	for i in _full_height_ticks():
		_air(m).request_dive(Vector2(10.0, 10.0))
		_air(m)._update_flying_height()
	assert_almost_eq(_air(m).height_offset(), 0.0, 0.02)


func test_flying_climbs_back_when_dive_not_requested():
	# Dive down, then stop requesting -> eases back to cruise altitude.
	var m := _make_flying(Vector3(10, 0, 10))
	for i in _full_height_ticks():
		_air(m).request_dive(Vector2(10.0, 10.0))
		_air(m)._update_flying_height()
	assert_lt(_air(m).height_offset(), 0.1, "precondition: dove to the ground")
	for i in _full_height_ticks():
		_air(m)._update_flying_height()  # no request this tick
	assert_almost_eq(_air(m).height_offset(), Aerial.AERIAL_HEIGHT, 0.02)


func test_flying_stays_at_altitude_for_far_target():
	# A dive request for a target beyond dive_distance keeps the unit at cruise altitude.
	var m := _make_flying(Vector3(10, 0, 10))
	for i in 30:
		_air(m).request_dive(Vector2(10.0 + _air(m).dive_distance * 5.0, 10.0))
		_air(m)._update_flying_height()
	assert_almost_eq(_air(m).height_offset(), Aerial.AERIAL_HEIGHT, 0.001)


#region FLYING airplane attitude
## A FLYING Movement with the MeshVisual real units carry, so attitude has somewhere to go.
func _make_flying_with_visual() -> Array:
	var parent := Node3D.new()
	add_child_autofree(parent)
	var visual := MeshVisual.new()
	visual.name = "MeshVisual"
	parent.add_child(visual)
	var m := Movement.new()
	m.name = "Locomotion"
	_add_aerial(parent, Movement.Mode.FLYING)
	parent.add_child(m)
	return [parent, m, visual]


func test_flying_noses_over_into_a_dive():
	var rig := _make_flying_with_visual()
	var m: Movement = rig[1]
	var visual: Node3D = rig[2]
	_fly_dive_run(m, Vector2(20.0, 0.0), 4.0)
	assert_gt(
		visual.rotation.x,
		deg_to_rad(30.0),
		"a terminal dive points the nose steeply down, not level"
	)


func test_flying_holds_its_nose_level_in_cruise():
	var rig := _make_flying_with_visual()
	var m: Movement = rig[1]
	var visual: Node3D = rig[2]
	for i in 60:
		m._current_velocity = Vector3(0, 0, 4.0)
		_air(m)._update_flying_height()  # no dive requested
	assert_almost_eq(visual.rotation.x, 0.0, 0.01, "level flight, level nose")


func test_flying_banks_into_a_turn():
	# Coordinated turn: the model rolls toward the side it is turning to, and a tighter
	# turn banks harder. Yaw rate is derived from the body's rotation.y between ticks.
	var rig := _make_flying_with_visual()
	var parent: Node3D = rig[0]
	var m: Movement = rig[1]
	var visual: Node3D = rig[2]
	var tps: float = float(TimeUtils.ticks_per_second())
	for i in 120:
		parent.rotation.y += deg_to_rad(90.0) / tps  # a steady 90 deg/s left turn
		m._current_velocity = Vector3(0, 0, 4.0)
		_air(m)._update_flying_height()
	var gentle: float = visual.rotation.z
	assert_gt(absf(gentle), deg_to_rad(5.0), "a sustained turn produces a real bank")

	var rig2 := _make_flying_with_visual()
	var parent2: Node3D = rig2[0]
	var m2: Movement = rig2[1]
	var visual2: Node3D = rig2[2]
	for i in 120:
		parent2.rotation.y += deg_to_rad(180.0) / tps  # twice the turn rate
		m2._current_velocity = Vector3(0, 0, 4.0)
		_air(m2)._update_flying_height()
	assert_gt(absf(visual2.rotation.z), absf(gentle), "a tighter turn banks harder")
	assert_eq(signf(visual2.rotation.z), signf(gentle), "and to the same side")


func test_flying_bank_is_capped():
	var rig := _make_flying_with_visual()
	var parent: Node3D = rig[0]
	var m: Movement = rig[1]
	var visual: Node3D = rig[2]
	var tps: float = float(TimeUtils.ticks_per_second())
	for i in 200:
		parent.rotation.y += deg_to_rad(720.0) / tps  # absurd turn rate
		m._current_velocity = Vector3(0, 0, 20.0)
		_air(m)._update_flying_height()
	assert_true(
		absf(visual.rotation.z) <= Aerial.FLYING_MAX_BANK + 1e-3, "bank never rolls past the cap"
	)


func test_flying_attitude_never_touches_the_physics_body():
	# Same guarantee as the hover lean: range/collision shapes hang off the body, so only
	# the model may pitch or roll.
	var rig := _make_flying_with_visual()
	var parent: Node3D = rig[0]
	var m: Movement = rig[1]
	var visual: Node3D = rig[2]
	var tps: float = float(TimeUtils.ticks_per_second())
	for i in 60:
		parent.rotation.y += deg_to_rad(90.0) / tps
		m._current_velocity = Vector3(0, 0, 4.0)
		_air(m)._update_flying_height()
	_fly_dive_run(m, Vector2(20.0, 0.0), 4.0)
	assert_ne(visual.rotation.x, 0.0, "precondition: the model is pitched")
	assert_almost_eq(parent.rotation.x, 0.0, 1e-9, "the body is never pitched")
	assert_almost_eq(parent.rotation.z, 0.0, 1e-9, "the body is never rolled")


func test_flying_attitude_is_safe_without_a_mesh_visual():
	var m := _make_flying(Vector3.ZERO)
	m._current_velocity = Vector3(0, 0, 4.0)
	_air(m)._update_flying_height()
	assert_almost_eq(_air(m).height_offset(), Aerial.AERIAL_HEIGHT, 0.1, "no crash, no lean")


#endregion


func test_request_dive_is_noop_outside_flying_mode():
	# A HOVERING unit ignores dive requests and holds its cruise altitude.
	var parent := Node3D.new()
	add_child_autofree(parent)
	var aerial := _add_aerial(parent, Movement.Mode.HOVERING)
	aerial.request_dive(Vector2(10, 10))
	aerial._update_flying_height()
	assert_almost_eq(aerial.height_offset(), Aerial.AERIAL_HEIGHT, 0.001)


#endregion


#region Grounded signed-speed acceleration
## _approach_signed_speed eases a signed longitudinal speed through zero under the
## accel/decel budget, and picks accel vs decel by whether the speed's magnitude is
## growing or shrinking. tps = 30, so a step is field/30 per tick.
func test_approach_signed_speed_selects_accel_and_decel():
	var m := Movement.new()
	add_child_autofree(m)
	m.max_acceleration = 1.5  # accel step 0.05/tick
	m.max_deceleration = -3.0  # decel step 0.10/tick (authored ≤ 0; used as a magnitude)
	# Braking a forward motion toward a reverse target uses deceleration, not a snap.
	assert_almost_eq(
		m._approach_signed_speed(1.8, -1.8, 30.0), 1.7, 1e-4, "forward brakes at decel"
	)
	# Easing straight through zero within one tick stays continuous.
	assert_almost_eq(
		m._approach_signed_speed(0.05, -1.8, 30.0), -0.05, 1e-4, "crosses zero smoothly"
	)
	# Below zero, building reverse speed uses acceleration.
	assert_almost_eq(
		m._approach_signed_speed(-0.05, -1.8, 30.0), -0.10, 1e-4, "reverse builds at accel"
	)
	# Speeding up forward uses acceleration.
	assert_almost_eq(
		m._approach_signed_speed(1.0, 1.8, 30.0), 1.05, 1e-4, "forward builds at accel"
	)


## Regression: a reverse command must NOT flip the emitted velocity straight to full
## reverse. With bounded deceleration the along-facing speed decelerates by one
## decel step instead of snapping to the opposite sign.
func test_grounded_reverse_command_does_not_snap_velocity():
	var parent := Node3D.new()
	add_child_autofree(parent)
	parent.rotation.y = 0.0  # facing = (0, 0, -1)
	var m := Movement.new()
	m.max_acceleration = 1.5
	m.max_deceleration = -3.0  # decel step 0.10/tick (authored ≤ 0)
	m.turn_rate = 90.0
	m.min_turn_speed_ratio = 1.0
	parent.add_child(m)  # _ready keeps the finite turn_rate

	var facing: Vector3 = m.get_facing()
	m._current_velocity = facing * 1.8  # driving forward at full speed
	# Command points directly behind the unit (reverse).
	var out: Vector3 = m._apply_grounded_turn(-facing * 1.8)

	# It brakes one decel step (1.8 -> 1.7), it does NOT jump to 1.8 in reverse.
	assert_almost_eq(out.length(), 1.7, 1e-3, "reverse decelerates by one step, no snap")
	assert_gt(out.dot(facing), 0.0, "still moving forward this tick, not flipped to reverse")


#endregion


#region Hovering bank/pitch attitude
## Helper: an AIRBORNE HOVERING Movement under a Node3D parent facing +Z (rotation.y
## == 0, so get_facing() == +Z and its right axis is +X), with the MeshVisual that
## real units carry.
##
## Pitch and roll go on the MODEL, not the body (Movement._attitude_node) — the body's
## children are the collision, aggro, vision and attack-range shapes, and leaning those
## displaced a unit's reach. So these tests assert on visual.rotation.{x,z}, and
## test_hover_bank_never_touches_the_physics_body guards the separation.
## Returns [parent, movement, visual].
func _make_hovering() -> Array:
	var parent := Node3D.new()
	add_child_autofree(parent)
	var visual := MeshVisual.new()
	visual.name = "MeshVisual"
	parent.add_child(visual)
	var m := Movement.new()
	m.name = "Locomotion"
	_add_aerial(parent, Movement.Mode.HOVERING)
	parent.add_child(m)  # triggers _ready
	return [parent, m, visual]


## Hold a constant acceleration (in world XZ) for `ticks` so the eased attitude settles
## on its target, then report it. Acceleration is derived as
## (_current_velocity - _prev_tilt_velocity) * tps, so a fixed pair of velocities one
## tick apart IS a fixed acceleration.
func _settle_lean(a_m: Movement, a_accel_xz: Vector2, a_ticks: int = 300) -> void:
	var tps: float = float(TimeUtils.ticks_per_second())
	var delta: Vector3 = Vector3(a_accel_xz.x, 0.0, a_accel_xz.y) / tps
	for i in a_ticks:
		_air(a_m)._prev_tilt_velocity = Vector3.ZERO
		a_m._current_velocity = delta
		_air(a_m)._apply_hover_bank()


func test_hover_bank_noses_down_when_accelerating_forward():
	var rig := _make_hovering()
	var m: Movement = rig[1]
	var visual: Node3D = rig[2]
	_settle_lean(m, Vector2(0.0, 1.0))  # thrust along +Z, the body's forward
	assert_gt(visual.rotation.x, 0.0, "accelerating forward noses the +Z front down")
	assert_almost_eq(visual.rotation.z, 0.0, 1e-6, "pure forward thrust produces no roll")


func test_hover_bank_noses_up_when_braking():
	var rig := _make_hovering()
	var m: Movement = rig[1]
	var visual: Node3D = rig[2]
	# Decelerating is thrust pointing BACKWARD, so the nose comes up — the flare a
	# helicopter pulls to stop. Under the old speed-driven pitch this read as a nose-DOWN
	# right up until the unit halted, which is what made braking look wrong.
	_settle_lean(m, Vector2(0.0, -1.0))
	assert_lt(visual.rotation.x, 0.0, "braking lifts the nose")
	assert_almost_eq(visual.rotation.z, 0.0, 1e-6, "pure longitudinal thrust produces no roll")


func test_hover_bank_stays_level_at_constant_velocity():
	var rig := _make_hovering()
	var m: Movement = rig[1]
	var visual: Node3D = rig[2]
	# The headline behaviour change: cruising flat out with no acceleration is LEVEL
	# flight. There is no thrust to tilt the rotor disc toward.
	for i in 300:
		m._current_velocity = Vector3(0, 0, m.speed)
		_air(m)._prev_tilt_velocity = m._current_velocity
		_air(m)._apply_hover_bank()
	assert_almost_eq(visual.rotation.x, 0.0, 1e-3, "constant velocity means no pitch")
	assert_almost_eq(visual.rotation.z, 0.0, 1e-3, "constant velocity means no roll")


func test_hover_bank_lean_scales_with_acceleration():
	var rig := _make_hovering()
	var m: Movement = rig[1]
	var visual: Node3D = rig[2]
	_settle_lean(m, Vector2(0.0, 1.0))
	var gentle: float = visual.rotation.x
	_settle_lean(m, Vector2(0.0, 2.0))
	assert_gt(visual.rotation.x, gentle, "harder thrust leans further")
	assert_almost_eq(
		gentle,
		1.0 * Aerial.HOVER_TILT_PER_ACCEL,
		1e-3,
		"and the lean is HOVER_TILT_PER_ACCEL radians per unit/s²"
	)


func test_hover_bank_rolls_into_rightward_acceleration():
	var rig := _make_hovering()
	var m: Movement = rig[1]
	var visual: Node3D = rig[2]
	_settle_lean(m, Vector2(1.0, 0.0))  # thrust along +X, the body's right
	assert_lt(visual.rotation.z, 0.0, "banks right: the inside (+X) side drops (-rotation.z)")
	assert_almost_eq(visual.rotation.x, 0.0, 1e-6, "no forward thrust component -> no pitch")


func test_hover_bank_leans_diagonally_into_a_diagonal_thrust():
	# The point of the whole change: the lean follows the acceleration DIRECTION around the
	# XZ plane, rather than being a forward-speed pitch plus a separate lateral roll.
	var rig := _make_hovering()
	var m: Movement = rig[1]
	var visual: Node3D = rig[2]
	_settle_lean(m, Vector2(1.0, 1.0))  # equal parts forward and right
	assert_gt(visual.rotation.x, 0.0, "the forward half of the thrust noses down")
	assert_lt(visual.rotation.z, 0.0, "the rightward half banks right")
	assert_almost_eq(
		visual.rotation.x,
		-visual.rotation.z,
		1e-6,
		"equal thrust components produce an equal, i.e. 45°, lean"
	)


func test_hover_bank_caps_the_lean_magnitude_not_each_axis():
	# A diagonal thrust must not lean sqrt(2) further than a straight one of the same
	# magnitude just because its demand splits across two axes.
	var rig := _make_hovering()
	var m: Movement = rig[1]
	var visual: Node3D = rig[2]
	var huge: float = Aerial.HOVER_MAX_LEAN / Aerial.HOVER_TILT_PER_ACCEL * 10.0
	_settle_lean(m, Vector2(0.0, huge))
	var straight: float = Vector2(visual.rotation.x, visual.rotation.z).length()
	assert_almost_eq(straight, Aerial.HOVER_MAX_LEAN, 1e-3, "straight thrust saturates the cap")
	_settle_lean(m, Vector2(huge, huge))
	var diagonal: float = Vector2(visual.rotation.x, visual.rotation.z).length()
	assert_almost_eq(
		diagonal,
		Aerial.HOVER_MAX_LEAN,
		1e-3,
		"and a diagonal one saturates at the same total lean, not sqrt(2) past it"
	)


func test_hover_bank_levels_out_when_thrust_stops():
	var rig := _make_hovering()
	var m: Movement = rig[1]
	var visual: Node3D = rig[2]
	_settle_lean(m, Vector2(0.0, 2.0))
	assert_gt(visual.rotation.x, 0.1, "precondition: leaning into the thrust")
	# ...then coast -> the nose returns to level.
	for i in 300:
		m._current_velocity = Vector3.ZERO
		_air(m)._prev_tilt_velocity = Vector3.ZERO
		_air(m)._apply_hover_bank()
	assert_almost_eq(visual.rotation.x, 0.0, 0.01, "no thrust relaxes to level")


func test_hover_bank_never_touches_the_physics_body():
	# The regression guard. AggroRange / VisionRange / AttackRange hang off the body as
	# 100-unit-tall cylinders, so any pitch or roll on it drags a unit's reach several
	# world units sideways. Yaw is the body's alone; pitch and roll are the model's alone.
	var rig := _make_hovering()
	var parent: Node3D = rig[0]
	var m: Movement = rig[1]
	var visual: Node3D = rig[2]
	# A diagonal thrust — accelerating forward and to the right at once — so the model
	# carries pitch AND roll simultaneously.
	_settle_lean(m, Vector2(2.0, 2.0))
	assert_ne(visual.rotation.x, 0.0, "precondition: the model is actually pitched")
	assert_ne(visual.rotation.z, 0.0, "precondition: the model is actually rolled")
	assert_almost_eq(parent.rotation.x, 0.0, 1e-9, "the body is never pitched")
	assert_almost_eq(parent.rotation.z, 0.0, 1e-9, "the body is never rolled")


func test_landing_and_takeoff_tilt_also_stays_on_the_model():
	var rig := _make_hovering()
	var parent: Node3D = rig[0]
	var m: Movement = rig[1]
	var visual: Node3D = rig[2]
	_air(m)._apply_hover_tilt(-Aerial.LANDING_SPEED)  # a descent's worth of vertical motion
	assert_gt(visual.rotation.x, 0.0, "descending noses the model down")
	assert_almost_eq(parent.rotation.x, 0.0, 1e-9, "and leaves the body level")


func test_attitude_helpers_are_safe_without_a_mesh_visual():
	# Billboard-art units have no MeshVisual; they simply don't lean rather than crash.
	var parent := Node3D.new()
	add_child_autofree(parent)
	var m := Movement.new()
	m.name = "Locomotion"
	_add_aerial(parent, Movement.Mode.HOVERING)
	parent.add_child(m)
	m._current_velocity = Vector3(0, 0, m.speed)
	_air(m)._apply_hover_bank()
	_air(m)._apply_hover_tilt(-Aerial.LANDING_SPEED)
	_air(m)._level_body()
	assert_almost_eq(parent.rotation.x, 0.0, 1e-9, "no MeshVisual, no lean, no crash")


#endregion


#region Landing / takeoff vertical acceleration
## _step_height_offset ramps the landing/takeoff rate under LANDING_ACCEL instead of
## snapping to a fixed per-tick step, so a descent eases off the hover and settles onto
## the ground rather than starting and stopping dead.
func _make_hovering_movement() -> Movement:
	var rig := _make_hovering()
	return rig[1]


func test_descent_starts_gently_rather_than_at_full_rate():
	var m := _make_hovering_movement()
	var first: float = absf(_air(m)._step_height_offset(0.0))
	var per_tick_cap: float = Aerial.LANDING_SPEED / float(TimeUtils.ticks_per_second())
	assert_lt(
		first, per_tick_cap * 0.5, "the first tick of a descent moves far less than the capped rate"
	)
	assert_gt(first, 0.0, "but it does start moving")


func test_descent_reaches_the_rate_cap_mid_manoeuvre():
	var m := _make_hovering_movement()
	for i in 60:
		_air(m)._step_height_offset(0.0)
	var per_tick_cap: float = Aerial.LANDING_SPEED / float(TimeUtils.ticks_per_second())
	assert_almost_eq(
		absf(_air(m)._landing_rate),
		Aerial.LANDING_SPEED,
		1e-3,
		"mid-descent it is travelling at the rate cap"
	)
	assert_true(absf(_air(m)._landing_rate) <= Aerial.LANDING_SPEED + 1e-6, "and never exceeds it")
	assert_gt(per_tick_cap, 0.0)


func test_descent_settles_exactly_on_the_ground_without_overshoot():
	var m := _make_hovering_movement()
	for i in 400:
		_air(m)._step_height_offset(0.0)
		assert_true(_air(m)._current_height_offset >= 0.0, "never dips below the ground")
	assert_almost_eq(_air(m)._current_height_offset, 0.0, 1e-6, "settles exactly on the ground")
	assert_almost_eq(_air(m)._landing_rate, 0.0, 1e-6, "and stops moving vertically")


func test_takeoff_settles_exactly_on_cruise_altitude():
	var m := _make_hovering_movement()
	_air(m)._current_height_offset = 0.0
	for i in 400:
		_air(m)._step_height_offset(Aerial.AERIAL_HEIGHT)
	assert_almost_eq(_air(m)._current_height_offset, Aerial.AERIAL_HEIGHT, 1e-6)
	assert_almost_eq(_air(m)._landing_rate, 0.0, 1e-6)


func test_a_reversal_eases_through_zero_rather_than_snapping():
	# land_permanently() during a takeoff flips the target mid-ascent. The rate must ramp
	# down through zero under LANDING_ACCEL, not invert in a single tick.
	var m := _make_hovering_movement()
	_air(m)._current_height_offset = 0.0
	for i in 60:
		_air(m)._step_height_offset(Aerial.AERIAL_HEIGHT)
	assert_gt(_air(m)._landing_rate, 0.0, "precondition: ascending")
	var dv_max: float = Aerial.LANDING_ACCEL / float(TimeUtils.ticks_per_second())
	var previous: float = _air(m)._landing_rate
	for i in 10:
		_air(m)._step_height_offset(0.0)
		assert_true(
			absf(_air(m)._landing_rate - previous) <= dv_max + 1e-6,
			"the rate changes by at most one acceleration step per tick"
		)
		previous = _air(m)._landing_rate


func test_seconds_to_change_offset_matches_a_trapezoidal_profile():
	var m := _make_hovering_movement()
	assert_almost_eq(_air(m)._seconds_to_change_offset(0.0), 0.0, 1e-9, "no distance, no time")
	# A full cruise-altitude descent: ramp up, cruise at the cap, ramp down.
	var ramp: float = Aerial.LANDING_SPEED * Aerial.LANDING_SPEED / Aerial.LANDING_ACCEL
	var expected: float = (
		2.0 * Aerial.LANDING_SPEED / Aerial.LANDING_ACCEL
		+ (Aerial.AERIAL_HEIGHT - ramp) / Aerial.LANDING_SPEED
	)
	assert_almost_eq(_air(m)._seconds_to_change_offset(Aerial.AERIAL_HEIGHT), expected, 1e-6)
	# A hop shorter than the ramp distance never reaches the cap — triangular profile.
	var short: float = ramp * 0.25
	assert_almost_eq(
		_air(m)._seconds_to_change_offset(short), 2.0 * sqrt(short / Aerial.LANDING_ACCEL), 1e-6
	)
	assert_eq(
		_air(m)._seconds_to_change_offset(-Aerial.AERIAL_HEIGHT),
		_air(m)._seconds_to_change_offset(Aerial.AERIAL_HEIGHT),
		"direction-agnostic"
	)


func test_the_estimate_agrees_with_the_stepper():
	# The steering and ascent-obstruction caps size themselves off
	# _seconds_to_change_offset, so it must actually predict what _step_height_offset does.
	var m := _make_hovering_movement()
	var predicted: float = _air(m)._seconds_to_change_offset(Aerial.AERIAL_HEIGHT)
	var ticks: int = 0
	while _air(m)._current_height_offset > 0.0 and ticks < 1000:
		_air(m)._step_height_offset(0.0)
		ticks += 1
	var actual: float = float(ticks) / float(TimeUtils.ticks_per_second())
	assert_almost_eq(actual, predicted, 0.1, "the predicted descent time matches the simulated one")


#endregion


#region Aerial altitude smoothing
## _step_smoothed_altitude is the acceleration-limited vertical controller that eases an
## aerial unit's followed terrain height toward a target. These exercise it directly
## (no Map needed); _update_aerial_altitude just feeds it a terrain target each tick.
func test_altitude_converges_to_constant_target():
	var m := Aerial.new()
	add_child_autofree(m)
	m._smoothed_terrain_y = 0.0
	m._vertical_velocity = 0.0
	for i in 300:
		m._step_smoothed_altitude(5.0)  # climb toward a 5-unit-higher plateau
	assert_almost_eq(m._smoothed_terrain_y, 5.0, 0.01, "settles onto the target height")
	assert_almost_eq(m._vertical_velocity, 0.0, 0.05, "and comes to rest there")


func test_altitude_respects_max_vertical_accel():
	var m := Aerial.new()
	add_child_autofree(m)
	m._smoothed_terrain_y = 0.0
	m._vertical_velocity = 0.0
	var dt: float = 1.0 / float(TimeUtils.ticks_per_second())
	var dv_max: float = Aerial.MAX_VERTICAL_ACCEL * dt
	# Against a huge target the controller wants maximum climb, but the per-tick change
	# in vertical speed can never exceed the acceleration budget.
	var prev_vy: float = m._vertical_velocity
	for i in 50:
		m._step_smoothed_altitude(1000.0)
		assert_lte(absf(m._vertical_velocity - prev_vy), dv_max + 1e-5, "accel stays within budget")
		prev_vy = m._vertical_velocity


func test_altitude_does_not_significantly_overshoot():
	var m := Aerial.new()
	add_child_autofree(m)
	m._smoothed_terrain_y = 0.0
	m._vertical_velocity = 0.0
	var peak: float = 0.0
	for i in 300:
		m._step_smoothed_altitude(3.0)
		peak = maxf(peak, m._smoothed_terrain_y)
	# The stopping-envelope approach settles onto the target without launching past it.
	assert_lt(peak, 3.0 + 0.25, "overshoot past the target stays small")


func test_altitude_descends_to_lower_target():
	var m := Aerial.new()
	add_child_autofree(m)
	m._smoothed_terrain_y = 5.0
	m._vertical_velocity = 0.0
	for i in 300:
		m._step_smoothed_altitude(1.0)  # ground drops away beneath the unit
	assert_almost_eq(m._smoothed_terrain_y, 1.0, 0.01, "eases down to the lower terrain")


#endregion


#region Crush
func _movement_of_class(a_class: Movement.CrushClass) -> Movement:
	var m := Movement.new()
	m.crush_class = a_class
	add_child_autofree(m)
	return m


func test_can_crush_needs_a_two_tier_gap():
	# One tier apart is not enough — crushing is reserved for a clear mismatch.
	var large := _movement_of_class(Movement.CrushClass.LARGE)
	assert_true(
		large.can_crush(_movement_of_class(Movement.CrushClass.SMALL)), "LARGE crushes SMALL"
	)
	assert_true(large.can_crush(_movement_of_class(Movement.CrushClass.TINY)), "LARGE crushes TINY")
	assert_false(
		large.can_crush(_movement_of_class(Movement.CrushClass.MEDIUM)), "LARGE spares MEDIUM"
	)
	assert_false(large.can_crush(_movement_of_class(Movement.CrushClass.HUGE)), "LARGE spares HUGE")


func test_can_crush_is_never_symmetric():
	var huge := _movement_of_class(Movement.CrushClass.HUGE)
	var tiny := _movement_of_class(Movement.CrushClass.TINY)
	assert_true(huge.can_crush(tiny))
	assert_false(tiny.can_crush(huge))


func test_can_crush_anything_gates_the_per_tick_scan():
	# Commandable._tick_crush() skips the whole scan when this is false, so it must
	# agree with can_crush(): false only when NO class could ever be crushed.
	for c: int in Movement.CrushClass.values():
		var mover := _movement_of_class(c)
		var crushes_something: bool = Movement.CrushClass.values().any(
			func(other: int) -> bool: return mover.can_crush(_movement_of_class(other))
		)
		assert_eq(
			mover.can_crush_anything(),
			crushes_something,
			"can_crush_anything() matches can_crush() for class %d" % c
		)


func _aerial_movement_of_class(a_class: Movement.CrushClass, a_mode: Movement.Mode) -> Movement:
	var parent := Node3D.new()
	add_child_autofree(parent)
	_add_aerial(parent, a_mode)
	var m := Movement.new()
	m.name = "Locomotion"
	m.crush_class = a_class
	parent.add_child(m)
	return m


func test_aerial_units_neither_crush_nor_are_crushed():
	# Crushing is a ground mechanic: the size gap is irrelevant the moment either side
	# is airborne. A HUGE gunship must not squash the TINY infantry it flies over, and
	# a HUGE tank must not squash a TINY aircraft above it.
	var ground_huge := _movement_of_class(Movement.CrushClass.HUGE)
	var ground_tiny := _movement_of_class(Movement.CrushClass.TINY)
	for aerial_mode: Movement.Mode in [Movement.Mode.HOVERING, Movement.Mode.FLYING]:
		var air_huge := _aerial_movement_of_class(Movement.CrushClass.HUGE, aerial_mode)
		var air_tiny := _aerial_movement_of_class(Movement.CrushClass.TINY, aerial_mode)
		assert_false(
			air_huge.can_crush(ground_tiny),
			"an aerial HUGE spares a grounded TINY (mode %d)" % aerial_mode
		)
		assert_false(
			ground_huge.can_crush(air_tiny),
			"a grounded HUGE spares an aerial TINY (mode %d)" % aerial_mode
		)
		assert_false(
			air_huge.can_crush(air_tiny),
			"two aerial units never crush each other (mode %d)" % aerial_mode
		)
	# Sanity: the same pairing on the ground still crushes, so the assertions above
	# are testing the aerial rule and not a broken size gap.
	assert_true(ground_huge.can_crush(ground_tiny), "grounded HUGE still crushes grounded TINY")


func test_can_crush_anything_skips_the_scan_for_aerial_units():
	# _tick_crush() bails on this, so an aerial crusher never runs the per-tick queries.
	for aerial_mode: Movement.Mode in [Movement.Mode.HOVERING, Movement.Mode.FLYING]:
		var air := _aerial_movement_of_class(Movement.CrushClass.HUGE, aerial_mode)
		assert_false(
			air.can_crush_anything(),
			"an aerial HUGE can crush nothing, so it skips the scan (mode %d)" % aerial_mode
		)


#endregion


#region Aerial destination convergence (turn-radius governor)
## Drive `m` toward its target the way CommandReceiver does — full-speed command each tick,
## Movement decides what it can actually do — and report the tick it arrived on, or -1.
## Also reports the closest it ever got, so a failure says how badly it orbited.
func _run_to_destination(a_m: Movement, a_target: Vector3, a_max_ticks: int = 900) -> Dictionary:
	var parent := a_m.get_parent() as Node3D
	var tps: float = float(TimeUtils.ticks_per_second())
	a_m.set_target_position(a_target)
	var closest: float = INF
	for i in a_max_ticks:
		if a_m.is_navigation_finished():
			return {"tick": i, "closest": closest}
		var to_target: Vector3 = a_m.get_next_path_position() - parent.global_position
		to_target.y = 0.0
		a_m.set_velocity(to_target.normalized() * a_m.speed)
		parent.global_position += a_m._current_velocity / tps
		closest = minf(closest, VU.in_xz(parent.global_position).distance_to(VU.in_xz(a_target)))
	return {"tick": -1, "closest": closest}


func _make_slerp_flyer(a_heading: Vector3) -> Movement:
	var m := _make_flying(Vector3.ZERO)
	m.speed = 4.0
	m.turn_rate = 120.0
	m._current_velocity = a_heading.normalized() * m.speed
	return m


func test_aerial_unit_reaches_a_destination_abeam_of_it():
	# The reported bug: a close destination off to the side sits inside the turning circle
	# (radius = 4.0 / 120 deg/s = 1.9 units), so the unit laps it forever.
	var m := _make_slerp_flyer(Vector3(0, 0, 1))  # flying +Z
	# destination abeam, 1 unit out
	var result: Dictionary = _run_to_destination(m, Vector3(1.0, 0, 0))
	assert_gt(
		result["tick"],
		0,
		"reaches a destination 1 unit abeam (closest approach %.2f)" % result["closest"]
	)


func test_aerial_unit_reaches_a_destination_behind_it():
	var m := _make_slerp_flyer(Vector3(0, 0, 1))
	var result: Dictionary = _run_to_destination(m, Vector3(0.5, 0, -1.5))
	assert_gt(
		result["tick"],
		0,
		"reaches a destination behind it (closest approach %.2f)" % result["closest"]
	)


func test_aerial_unit_reaches_destinations_all_around_it():
	# Sweep the full circle at a radius well inside the ungoverned turn radius.
	for deg: int in range(0, 360, 30):
		var m := _make_slerp_flyer(Vector3(0, 0, 1))
		var a: float = deg_to_rad(float(deg))
		var target := Vector3(cos(a) * 1.2, 0.0, sin(a) * 1.2)
		var result: Dictionary = _run_to_destination(m, target)
		assert_gt(
			result["tick"],
			0,
			"reaches a destination at %d deg (closest approach %.2f)" % [deg, result["closest"]]
		)


func test_governor_does_not_slow_a_straight_run_in():
	# A destination dead ahead needs no turn, so the unit must not be throttled.
	var m := _make_slerp_flyer(Vector3(0, 0, 1))
	m.set_target_position(Vector3(0, 0, 20))
	assert_almost_eq(
		m._turn_limited_speed(m.speed), m.speed, 1e-3, "a target dead ahead is uncapped"
	)


func test_governor_throttles_hardest_for_a_close_abeam_target():
	var m := _make_slerp_flyer(Vector3(0, 0, 1))
	m.set_target_position(Vector3(1.0, 0, 0))  # abeam, close
	var close_cap: float = m._turn_limited_speed(m.speed)
	m.set_target_position(Vector3(6.0, 0, 0))  # abeam, far
	var far_cap: float = m._turn_limited_speed(m.speed)
	assert_lt(close_cap, far_cap, "a closer abeam target demands a tighter turn, so less speed")
	assert_lt(close_cap, m.speed, "and it is genuinely a cap")


func test_governor_leaves_the_idle_orbit_alone():
	# A FLYING unit deliberately circles its anchor when idle; that is not a stuck orbit and
	# must not be throttled. Navigation being finished is what distinguishes them.
	var m := _make_slerp_flyer(Vector3(0, 0, 1))
	m.set_target_position(m.get_parent().global_position)  # already there
	assert_true(m.is_navigation_finished(), "precondition: navigation finished")
	assert_almost_eq(m._turn_limited_speed(m.speed), m.speed, 1e-3, "idle orbit is ungoverned")


#endregion


func test_aerial_unit_reaches_destinations_with_bounded_acceleration():
	# The governor asks the unit to slow down; a unit with bounded deceleration cannot
	# comply instantly, so it will overshoot before it tightens up. It must still converge.
	# Values mirror the kamikaze (speed 4, turn 120 deg/s, decel -2.0).
	for deg: int in range(0, 360, 45):
		var m := _make_slerp_flyer(Vector3(0, 0, 1))
		m.max_acceleration = 5.0
		m.max_deceleration = -2.0
		var a: float = deg_to_rad(float(deg))
		var target := Vector3(cos(a) * 1.2, 0.0, sin(a) * 1.2)
		var result: Dictionary = _run_to_destination(m, target)
		assert_gt(
			result["tick"],
			0,
			(
				"bounded-accel unit reaches a destination at %d deg (closest %.2f)"
				% [deg, result["closest"]]
			)
		)


#region Orbit entry after arriving at a destination
## Fly the idle orbit for `ticks` and report how the heading turned:
##   "total" — absolute turning summed over the run
##   "net"   — SIGNED turning summed over the run
## A clean entry sweeps one way and then keeps going that way around the circle, so
## |net| ~= total. Turning out and back drives |net| well below total, which is the
## signature of the double turn regardless of how far round the orbit the run gets.
func _orbit_entry_profile(a_m: Movement, a_ticks: int = 90) -> Dictionary:
	var parent := a_m.get_parent() as Node3D
	var tps: float = float(TimeUtils.ticks_per_second())
	var total: float = 0.0
	var net: float = 0.0
	var prev: float = atan2(VU.in_xz(a_m._current_velocity).y, VU.in_xz(a_m._current_velocity).x)
	for i in a_ticks:
		a_m.set_velocity(_air(a_m).compute_orbit_velocity())
		parent.global_position += a_m._current_velocity / tps
		var h: Vector2 = VU.in_xz(a_m._current_velocity)
		if h.is_zero_approx():
			continue
		var ang: float = atan2(h.y, h.x)
		var d: float = angle_difference(prev, ang)
		total += absf(d)
		net += d
		prev = ang
	return {"total": total, "net": net, "straightness": absf(net) / total if total > 1e-6 else 1.0}


## A FLYING unit that has just arrived at `dest` — sitting on it, still carrying its
## approach heading, with the sub-tolerance jitter a real arrival leaves behind.
func _arrived_flyer(a_heading: Vector3, a_jitter: Vector2) -> Movement:
	var m := _make_flying(Vector3.ZERO)
	m.speed = 4.0
	m.turn_rate = 120.0
	var parent := m.get_parent() as Node3D
	parent.global_position = Vector3(a_jitter.x, 0.0, a_jitter.y)
	m._current_velocity = a_heading.normalized() * _air(m).orbit_speed
	return m


func test_orbit_entry_does_not_double_back_on_arrival():
	# The reported bug: the unit turned away — often a full reversal — flew out, then turned
	# again onto the orbit. The anchor is the destination it just arrived at, so the offset
	# is arrival jitter and carries no direction; seeding the orbit from it (or from the
	# stale previous angle) aimed the first ideal point anywhere at all.
	for deg: int in range(0, 360, 45):
		var a: float = deg_to_rad(float(deg))
		var heading := Vector3(cos(a), 0.0, sin(a))
		# Jitter well inside the 0.125 arrival tolerance, deliberately opposing the heading —
		# the worst case for seeding off the offset.
		var m := _arrived_flyer(heading, -VU.in_xz(heading) * 0.05)
		_air(m).set_anchor(m.get_parent().global_position)
		var profile: Dictionary = _orbit_entry_profile(m)
		assert_gt(
			profile["straightness"],
			0.95,
			(
				"entering the orbit from heading %d deg turns one way throughout (straightness %.2f)"
				% [deg, profile["straightness"]]
			)
		)


func test_orbit_entry_turns_one_consistent_way():
	# A clean entry is a single sweep onto the circle. A there-and-back shows up as net
	# turning far smaller than the total swung, so require the net to carry the motion.
	var m := _arrived_flyer(Vector3(0, 0, 1), Vector2(0.03, -0.04))
	_air(m).set_anchor(m.get_parent().global_position)
	var profile: Dictionary = _orbit_entry_profile(m)
	assert_gt(
		profile["straightness"],
		0.95,
		"the entry keeps turning one way rather than turning back on itself"
	)


func test_orbit_entry_from_a_stale_angle_still_follows_the_heading():
	# First-ever loiter: _orbit_angle is still 0 (due +X). A unit arriving westbound used to
	# reverse to chase an ideal point due east of it.
	var m := _arrived_flyer(Vector3(-1, 0, 0), Vector2.ZERO)
	_air(m)._orbit_angle = 0.0
	_air(m).set_anchor(m.get_parent().global_position)
	assert_almost_eq(
		_air(m)._orbit_angle,
		PI,
		0.01,
		"the orbit clock is seeded from the heading, not left pointing due +X"
	)


func test_orbit_entry_off_centre_still_uses_its_bearing():
	# An anchor set while the unit is genuinely elsewhere: its bearing IS meaningful, so
	# that path must be preserved.
	var m := _make_flying(Vector3.ZERO)
	var parent := m.get_parent() as Node3D
	parent.global_position = Vector3(_air(m).orbit_radius, 0.0, 0.0)
	m._current_velocity = Vector3(0, 0, _air(m).orbit_speed)
	_air(m).set_anchor(Vector3.ZERO)
	assert_almost_eq(
		_air(m)._orbit_angle,
		0.0,
		0.01,
		"seeded from the bearing (due +X of the anchor), not the heading"
	)
#endregion
