extends GutTest

## Who yields to whom in same-team RVO: a unit ENGAGED (standing its ground to fire) yields
## to nobody, and one TRAVELLING outranks one standing still, so the traveller holds its
## heading and the stander gives way.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_AvoidanceYielding.gd -gexit
##
## RVO is reciprocal — two equal-priority agents each take half the responsibility for not
## colliding — so a stationary neighbour that never pays its half leaves the mover
## re-steering around it, and the mover arcs. That was the whole of the "why do my units
## walk in L shapes" report: ordered five tiles diagonally out of s3's opening group (one
## squadmate standing exactly on its line), a unit bowed 0.39 cells sideways and travelled
## in legs at 63°, 34° and 41° instead of a clean 45° — over a path that was already
## exactly straight. Ranking travellers above standers measured 0.000 lateral deviation,
## with the closest approach between bodies unchanged at 0.41 (2x the 0.2 agent radius), and
## the bystander stepping ~0.4 cells aside instead. The work is conserved, not removed; this
## chooses who does it.
##
## A live NavigationServer can't be driven headlessly (see test_Movement), so the behaviour
## above is not re-measured here — what is pinned is the ranking that produces it, which is
## the part that can silently regress.

var _agent: AvoidanceAgent3D
var _movement: Movement


## A Movement wrapping a real AvoidanceAgent3D — the same fixture shape test_AvoidanceLayers
## uses. `finished` drives what is_navigation_finished() reports: a unit with no target is
## finished, and one given a distant target is not. The target goes through Movement, which
## owns the path — the agent only carries it for avoidance.
func _make_movement(a_finished: bool) -> Movement:
	var parent := Node3D.new()
	add_child_autofree(parent)
	_agent = AvoidanceAgent3D.new()
	_agent.name = "NavigationAgent"
	parent.add_child(_agent)
	_movement = Movement.new()
	_movement.nav_agent_path = NodePath("../NavigationAgent")
	parent.add_child(_movement)  # _ready resolves _nav_agent
	if not a_finished:
		_movement.target_position = parent.global_position + Vector3(50, 0, 50)
	return _movement


func test_the_tiers_are_strictly_ordered() -> void:
	# Everything else here rests on this ordering: Godot's avoidance_priority makes an agent
	# skip adjusting for LOWER-priority neighbours, pushing the adjustment onto them.
	assert_lt(Movement.AVOIDANCE_PRIORITY_STANDING, Movement.AVOIDANCE_PRIORITY_TRAVELLING,
		"a standing unit must rank below a travelling one")
	assert_lt(Movement.AVOIDANCE_PRIORITY_TRAVELLING, Movement.AVOIDANCE_PRIORITY_ENGAGED,
		"a travelling unit must rank below one holding ground to fire")


func test_engaged_is_the_engine_ceiling() -> void:
	# NavigationAgent3D clamps avoidance_priority to [0, 1]; at the ceiling nothing on the
	# team can outrank a unit holding ground.
	assert_eq(Movement.AVOIDANCE_PRIORITY_ENGAGED, 1.0)


func test_a_stationary_unit_yields() -> void:
	var movement: Movement = _make_movement(true)
	movement.update_avoidance_priority(false)
	assert_eq(_agent.avoidance_priority, Movement.AVOIDANCE_PRIORITY_STANDING,
		"a unit that is not going anywhere gives way")


func test_a_travelling_unit_holds_its_rank() -> void:
	var movement: Movement = _make_movement(false)
	movement.update_avoidance_priority(false)
	assert_eq(_agent.avoidance_priority, Movement.AVOIDANCE_PRIORITY_TRAVELLING,
		"a unit with somewhere to be outranks the ones standing around")


func test_a_unit_holding_ground_yields_to_nobody() -> void:
	# Stationary and firing: the agent is finished navigating, but the order says hold.
	var movement: Movement = _make_movement(true)
	movement.update_avoidance_priority(true)
	assert_eq(_agent.avoidance_priority, Movement.AVOIDANCE_PRIORITY_ENGAGED,
		"a unit firing from where it stands is not shoved aside by its own side")


func test_the_rank_follows_what_the_unit_is_doing_now() -> void:
	# Re-evaluated every tick from Commandable._physics_process rather than latched when a
	# command is issued, so a unit regains its rank the moment it starts moving and drops it
	# again on arrival.
	var movement: Movement = _make_movement(true)
	movement.update_avoidance_priority(true)
	assert_eq(_agent.avoidance_priority, Movement.AVOIDANCE_PRIORITY_ENGAGED)
	movement.update_avoidance_priority(false)
	assert_eq(_agent.avoidance_priority, Movement.AVOIDANCE_PRIORITY_STANDING,
		"ceasing fire drops it to a stander")
	_movement.target_position = Vector3(50, 0, 50)
	movement.update_avoidance_priority(false)
	assert_eq(_agent.avoidance_priority, Movement.AVOIDANCE_PRIORITY_TRAVELLING,
		"setting off restores the traveller's rank")


func test_an_aerial_unit_is_left_alone() -> void:
	# HOVERING / FLYING units have no NavigationAgent3D and no RVO at all.
	var host := Node3D.new()
	add_child_autofree(host)
	var aerial := Aerial.new()
	aerial.name = "Aerial"
	aerial.mode = Movement.Mode.HOVERING
	host.add_child(aerial)
	var movement := Movement.new()
	host.add_child(movement)
	movement.update_avoidance_priority(true)  # must not touch anything, must not crash
	assert_null(movement.avoidance_agent(), "an aerial unit has no avoidance agent")
