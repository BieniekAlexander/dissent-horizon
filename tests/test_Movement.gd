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
	assert_ne(mask & AvoidanceAgent3D.team_bit(2), 0, "masks own team bit (same-team reciprocal RVO)")
	assert_ne(mask & AvoidanceAgent3D.obstacle_bit(1), 0, "masks a foreign commander's obstacle bit")
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
func _make_flying(pos: Vector3) -> Movement:
	var parent := Node3D.new()
	add_child_autofree(parent)
	parent.global_position = pos
	var m := Movement.new()
	m.mode = Movement.Mode.FLYING
	parent.add_child(m)  # triggers _ready
	return m

func test_flying_starts_at_cruise_altitude():
	var m := _make_flying(Vector3(10, 0, 10))
	assert_almost_eq(m.height_offset(), Movement.AERIAL_HEIGHT, 0.001)

func test_flying_dive_descends_proportional_to_distance():
	# Target half a dive_distance away -> settles at half cruise altitude.
	var m := _make_flying(Vector3(10, 0, 10))
	var tgt := Vector2(10.0 + m.dive_distance * 0.5, 10.0)
	for i in 100:
		m.request_dive(tgt)
		m._update_flying_height()
	assert_almost_eq(m.height_offset(), Movement.AERIAL_HEIGHT * 0.5, 0.02)

## Ticks to fully descend/ascend the cruise altitude at LANDING_SPEED, with headroom —
## derived from the constants so the tests hold if AERIAL_HEIGHT changes.
func _full_height_ticks() -> int:
	return int(ceil(Movement.AERIAL_HEIGHT / Movement.LANDING_SPEED)) + 20

func test_flying_dive_onto_target_reaches_ground():
	# Diving straight onto the target's XZ (distance 0) drops to ~ground level.
	var m := _make_flying(Vector3(10, 0, 10))
	for i in _full_height_ticks():
		m.request_dive(Vector2(10.0, 10.0))
		m._update_flying_height()
	assert_almost_eq(m.height_offset(), 0.0, 0.02)

func test_flying_climbs_back_when_dive_not_requested():
	# Dive down, then stop requesting -> eases back to cruise altitude.
	var m := _make_flying(Vector3(10, 0, 10))
	for i in _full_height_ticks():
		m.request_dive(Vector2(10.0, 10.0))
		m._update_flying_height()
	assert_lt(m.height_offset(), 0.1, "precondition: dove to the ground")
	for i in _full_height_ticks():
		m._update_flying_height()  # no request this tick
	assert_almost_eq(m.height_offset(), Movement.AERIAL_HEIGHT, 0.02)

func test_flying_stays_at_altitude_for_far_target():
	# A dive request for a target beyond dive_distance keeps the unit at cruise altitude.
	var m := _make_flying(Vector3(10, 0, 10))
	for i in 30:
		m.request_dive(Vector2(10.0 + m.dive_distance * 5.0, 10.0))
		m._update_flying_height()
	assert_almost_eq(m.height_offset(), Movement.AERIAL_HEIGHT, 0.001)

func test_request_dive_is_noop_outside_flying_mode():
	# A GROUNDED_DIRECT unit ignores dive requests and keeps a zero height offset.
	var parent := Node3D.new()
	add_child_autofree(parent)
	var m := Movement.new()
	m.mode = Movement.Mode.GROUNDED_DIRECT
	parent.add_child(m)
	m.request_dive(Vector2(10, 10))
	assert_almost_eq(m.height_offset(), 0.0, 0.001)
#endregion

#region Grounded signed-speed acceleration
## _approach_signed_speed eases a signed longitudinal speed through zero under the
## accel/decel budget, and picks accel vs decel by whether the speed's magnitude is
## growing or shrinking. tps = 30, so a step is field/30 per tick.
func test_approach_signed_speed_selects_accel_and_decel():
	var m := Movement.new()
	add_child_autofree(m)
	m.max_acceleration = 1.5    # accel step 0.05/tick
	m.max_deceleration = -3.0   # decel step 0.10/tick (authored ≤ 0; used as a magnitude)
	# Braking a forward motion toward a reverse target uses deceleration, not a snap.
	assert_almost_eq(m._approach_signed_speed(1.8, -1.8, 30.0), 1.7, 1e-4, "forward brakes at decel")
	# Easing straight through zero within one tick stays continuous.
	assert_almost_eq(m._approach_signed_speed(0.05, -1.8, 30.0), -0.05, 1e-4, "crosses zero smoothly")
	# Below zero, building reverse speed uses acceleration.
	assert_almost_eq(m._approach_signed_speed(-0.05, -1.8, 30.0), -0.10, 1e-4, "reverse builds at accel")
	# Speeding up forward uses acceleration.
	assert_almost_eq(m._approach_signed_speed(1.0, 1.8, 30.0), 1.05, 1e-4, "forward builds at accel")


## Regression: a reverse command must NOT flip the emitted velocity straight to full
## reverse. With bounded deceleration the along-facing speed decelerates by one
## decel step instead of snapping to the opposite sign.
func test_grounded_reverse_command_does_not_snap_velocity():
	var parent := Node3D.new()
	add_child_autofree(parent)
	parent.rotation.y = 0.0            # facing = (0, 0, -1)
	var m := Movement.new()
	m.mode = Movement.Mode.GROUNDED_DIRECT
	m.max_acceleration = 1.5
	m.max_deceleration = -3.0          # decel step 0.10/tick (authored ≤ 0)
	m.turn_rate = 90.0
	m.min_turn_speed_ratio = 1.0
	parent.add_child(m)                # _ready keeps the finite turn_rate

	var facing: Vector3 = m.get_facing()
	m._current_velocity = facing * 1.8            # driving forward at full speed
	# Command points directly behind the unit (reverse).
	var out: Vector3 = m._apply_grounded_turn(-facing * 1.8)

	# It brakes one decel step (1.8 -> 1.7), it does NOT jump to 1.8 in reverse.
	assert_almost_eq(out.length(), 1.7, 1e-3, "reverse decelerates by one step, no snap")
	assert_gt(out.dot(facing), 0.0, "still moving forward this tick, not flipped to reverse")
#endregion

#region Hovering bank/pitch attitude
## Helper: an AIRBORNE HOVERING Movement under a Node3D parent facing +Z (rotation.y
## == 0, so get_facing() == +Z and its right axis is +X). Bank helpers read the
## parent's rotation, so tests assert on parent.rotation.{x,z}.
func _make_hovering() -> Array:
	var parent := Node3D.new()
	add_child_autofree(parent)
	var m := Movement.new()
	m.mode = Movement.Mode.HOVERING
	parent.add_child(m)  # triggers _ready (seeds AIRBORNE + cruise altitude)
	return [parent, m]


func test_hover_bank_noses_down_while_cruising_forward():
	var pair := _make_hovering()
	var parent: Node3D = pair[0]
	var m: Movement = pair[1]
	# Steady forward velocity (zero acceleration) — pitch is speed-based, so the nose
	# still dips: it tracks how fast the unit flies, not whether it's accelerating.
	m._current_velocity = Vector3(0, 0, m.speed * 0.5)
	m._prev_tilt_velocity = m._current_velocity
	m._apply_hover_bank()
	assert_gt(parent.rotation.x, 0.0, "forward flight noses the +Z front down")
	assert_almost_eq(parent.rotation.z, 0.0, 1e-6, "straight-line flight produces no roll")


func test_hover_bank_noses_up_when_flying_backward():
	var pair := _make_hovering()
	var parent: Node3D = pair[0]
	var m: Movement = pair[1]
	# Sliding backward (velocity opposes facing) lifts the nose.
	m._current_velocity = Vector3(0, 0, -m.speed * m.reverse_speed_ratio * 0.5)
	m._prev_tilt_velocity = m._current_velocity
	m._apply_hover_bank()
	assert_lt(parent.rotation.x, 0.0, "reverse flight noses up")


func test_hover_bank_pitch_scales_with_forward_speed():
	var pair := _make_hovering()
	var parent: Node3D = pair[0]
	var m: Movement = pair[1]
	# Full forward speed converges to the max nose-down angle.
	for i in 200:
		m._current_velocity = Vector3(0, 0, m.speed)
		m._prev_tilt_velocity = m._current_velocity
		m._apply_hover_bank()
	assert_almost_eq(parent.rotation.x, Movement.HOVER_MAX_PITCH, 1e-3, "full speed saturates pitch")


func test_hover_bank_pitch_is_clamped_above_top_speed():
	var pair := _make_hovering()
	var parent: Node3D = pair[0]
	var m: Movement = pair[1]
	# Even an over-speed velocity can't pitch past the cap.
	for i in 200:
		m._current_velocity = Vector3(0, 0, m.speed * 3.0)
		m._prev_tilt_velocity = m._current_velocity
		m._apply_hover_bank()
	assert_almost_eq(parent.rotation.x, Movement.HOVER_MAX_PITCH, 1e-3, "pitch never exceeds the cap")


func test_hover_bank_rolls_into_rightward_acceleration():
	var pair := _make_hovering()
	var parent: Node3D = pair[0]
	var m: Movement = pair[1]
	m._prev_tilt_velocity = Vector3.ZERO
	m._current_velocity = Vector3(2.0, 0, 0)  # accelerating along +X (the body's right)
	m._apply_hover_bank()
	assert_lt(parent.rotation.z, 0.0, "banks right: the inside (+X) side drops (-rotation.z)")
	assert_almost_eq(parent.rotation.x, 0.0, 1e-6, "no forward-speed component -> no pitch")


func test_hover_bank_levels_out_when_stopped():
	var pair := _make_hovering()
	var parent: Node3D = pair[0]
	var m: Movement = pair[1]
	# Build up a lean...
	for i in 30:
		m._current_velocity = Vector3(0, 0, m.speed)
		m._prev_tilt_velocity = m._current_velocity
		m._apply_hover_bank()
	assert_gt(parent.rotation.x, 0.1, "precondition: leaning forward")
	# ...then come to rest -> the nose returns to level.
	for i in 100:
		m._current_velocity = Vector3.ZERO
		m._prev_tilt_velocity = Vector3.ZERO
		m._apply_hover_bank()
	assert_almost_eq(parent.rotation.x, 0.0, 0.01, "hovering in place relaxes to level")
#endregion

#region Aerial altitude smoothing
## _step_smoothed_altitude is the acceleration-limited vertical controller that eases an
## aerial unit's followed terrain height toward a target. These exercise it directly
## (no Map needed); _update_aerial_altitude just feeds it a terrain target each tick.
func test_altitude_converges_to_constant_target():
	var m := Movement.new()
	add_child_autofree(m)
	m._smoothed_terrain_y = 0.0
	m._vertical_velocity = 0.0
	for i in 300:
		m._step_smoothed_altitude(5.0)  # climb toward a 5-unit-higher plateau
	assert_almost_eq(m._smoothed_terrain_y, 5.0, 0.01, "settles onto the target height")
	assert_almost_eq(m._vertical_velocity, 0.0, 0.05, "and comes to rest there")


func test_altitude_respects_max_vertical_accel():
	var m := Movement.new()
	add_child_autofree(m)
	m._smoothed_terrain_y = 0.0
	m._vertical_velocity = 0.0
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	var dv_max: float = Movement.MAX_VERTICAL_ACCEL * dt
	# Against a huge target the controller wants maximum climb, but the per-tick change
	# in vertical speed can never exceed the acceleration budget.
	var prev_vy: float = m._vertical_velocity
	for i in 50:
		m._step_smoothed_altitude(1000.0)
		assert_lte(absf(m._vertical_velocity - prev_vy), dv_max + 1e-5, "accel stays within budget")
		prev_vy = m._vertical_velocity


func test_altitude_does_not_significantly_overshoot():
	var m := Movement.new()
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
	var m := Movement.new()
	add_child_autofree(m)
	m._smoothed_terrain_y = 5.0
	m._vertical_velocity = 0.0
	for i in 300:
		m._step_smoothed_altitude(1.0)  # ground drops away beneath the unit
	assert_almost_eq(m._smoothed_terrain_y, 1.0, 0.01, "eases down to the lower terrain")
#endregion
