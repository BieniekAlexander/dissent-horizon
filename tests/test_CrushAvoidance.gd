extends GutTest

## A CRUSHER DOES NOT STEER AROUND WHAT IT IS ABOUT TO DRIVE OVER.
##
## Three rules, and all three are asserted below against the avoidance bits themselves
## (AvoidanceAgent3D's layout: team channels 0-7, obstacle channels 8-15):
##
##   1. Same team -> always reciprocal RVO, crush or no crush.
##   2. X can crush Y -> X ignores Y and paths through it.
##   3. X can crush Y -> Y still treats X as an obstacle and paths around it.
##
## The bug this guards against: the exclusion used to be scanned within AGGRO RANGE, which
## is a different question — "how far will I pick a fight" — and one a peaceful crusher
## deliberately has no answer to. A dominion generator, a transport and a truck all carry no
## aggro volume, so they excluded nothing ever and politely walked around the infantry they
## outweigh. See Commandable._update_crush_avoidance_exclusions.
##
## Scenes are load()ed INSIDE the tests, never preloaded at file scope — see
## test_CaptureByCrushing and CLAUDE.md §Running and testing.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gexit \
##     -gtest=res://tests/test_CrushAvoidance.gd

## MEDIUM crush class, and a hold — the piece the reported bug was seen on.
const CRUSHER_PATH: Dictionary = {"speed": 2.0, "vision": 8.0, "crush": Movement.CrushClass.LARGE}
## TINY: two classes below the crusher, so it is crushable.
## Light infantry: small enough to be crushed.
const VICTIM_PATH: Dictionary = {"speed": 1.0, "vision": 8.0}
## MEDIUM, same class as the crusher: outside the crush gap, so it is not crushable.
## As big as the crusher, so not crushable.
const PEER_PATH: Dictionary = {"speed": 1.0, "vision": 8.0, "crush": Movement.CrushClass.LARGE}
const PLAYER: int = 1
const ENEMY: int = 2


func _entity(a_options: Dictionary, a_commander_id: int, a_at: Vector3) -> Commandable:
	var c := Commander.new()
	c.id = a_commander_id
	add_child_autofree(c)
	var e := FakePieces.make(a_options) as Commandable
	add_child_autofree(e)
	e.ownership.commander = c
	e.global_position = a_at
	return e


## A crusher with NO aggro volume — built here rather than taken from the roster, so this
## file tests the mechanic and not whichever pieces happen to be authored without one
## (CLAUDE.md §A unit test does not assert facts about authored content). Its own physics
## is switched off so it cannot crush, capture or drive off mid-test; the function under
## test is driven by hand.
func _crusher_without_aggro(a_at: Vector3 = Vector3.ZERO) -> Commandable:
	var crusher: Commandable = _entity(CRUSHER_PATH, PLAYER, a_at)
	crusher.set_physics_process(false)
	for shape_node: CollisionShape3D in crusher.aggro_shapes():
		shape_node.shape = null
	return crusher


func _agent(a_unit: Commandable) -> AvoidanceAgent3D:
	return a_unit.movement.avoidance_agent()


func _avoids_obstacle_of(a_unit: Commandable, a_other: Commandable) -> bool:
	return (_agent(a_unit).avoidance_mask
		& AvoidanceAgent3D.obstacle_bit(a_other.commander_id)) != 0


## Settle the physics space so the shape query in the function under test can see the
## bodies, then recompute `a_crusher`'s exclusions.
func _settle_and_update(a_crusher: Commandable) -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	a_crusher._update_crush_avoidance_exclusions()


#region Rule 2 — the crusher paths through what it can crush
func test_a_crusher_with_no_aggro_volume_still_ignores_what_it_can_crush() -> void:
	# THE REPORTED BUG. Nothing about driving over a soldier is a question about aggro
	# range, so having none must not silence the mechanic.
	var crusher: Commandable = _crusher_without_aggro()
	var victim: Commandable = _entity(VICTIM_PATH, ENEMY, Vector3(1.5, 0, 0))
	assert_true(crusher._can_run_over(victim), "precondition: it is crushable prey")
	assert_true(_avoids_obstacle_of(crusher, victim), "precondition: it starts out avoiding it")

	await _settle_and_update(crusher)

	assert_false(_avoids_obstacle_of(crusher, victim),
		"the crusher stops steering around prey it is about to drive over")


func test_a_peer_it_cannot_crush_is_still_avoided() -> void:
	# The exclusion must follow the crush gap, not merely "is an enemy nearby".
	var crusher: Commandable = _crusher_without_aggro()
	var peer: Commandable = _entity(PEER_PATH, ENEMY, Vector3(1.5, 0, 0))
	assert_false(crusher._can_run_over(peer), "precondition: same crush class, not prey")

	await _settle_and_update(crusher)

	assert_true(_avoids_obstacle_of(crusher, peer),
		"a vehicle it cannot run over is still an obstacle")


func test_prey_outside_the_rvo_neighbourhood_changes_nothing() -> void:
	# Scoped to the region RVO actually reacts within: beyond it there is nothing to stop
	# steering around, because no steering was happening.
	var crusher: Commandable = _crusher_without_aggro()
	var far: float = _agent(crusher).neighbor_distance * 4.0
	var victim: Commandable = _entity(VICTIM_PATH, ENEMY, Vector3(far, 0, 0))
	assert_true(crusher._can_run_over(victim), "precondition: crushable, just distant")

	await _settle_and_update(crusher)

	assert_true(_avoids_obstacle_of(crusher, victim),
		"a distant enemy is still an obstacle")
#endregion


#region Rule 1 — same team always respects itself
func test_a_friendly_is_never_run_over_and_keeps_reciprocal_rvo() -> void:
	var crusher: Commandable = _crusher_without_aggro()
	var friend: Commandable = _entity(VICTIM_PATH, PLAYER, Vector3(1.5, 0, 0))
	assert_false(crusher._can_run_over(friend),
		"same team is not prey however big the size gap")

	await _settle_and_update(crusher)

	assert_ne(_agent(crusher).avoidance_mask & AvoidanceAgent3D.team_bit(PLAYER), 0,
		"the crusher still does reciprocal RVO with its own team")


func test_crushing_prey_does_not_disturb_same_team_rvo() -> void:
	# The exclusion works on foreign OBSTACLE channels; the same-team reciprocal channel is
	# a different set of bits and must come through untouched.
	var crusher: Commandable = _crusher_without_aggro()
	var prey: Commandable = _entity(VICTIM_PATH, ENEMY, Vector3(1.5, 0, 0))
	assert_true(crusher._can_run_over(prey), "precondition: there is prey to exclude")
	var team_bit: int = AvoidanceAgent3D.team_bit(PLAYER)

	await _settle_and_update(crusher)

	assert_ne(_agent(crusher).avoidance_mask & team_bit, 0,
		"own-team RVO survives an active crush exclusion")
#endregion


#region Rule 3 — the prey still gets out of the way
func test_the_victim_still_treats_its_crusher_as_an_obstacle() -> void:
	# One-sided by design: the crusher walks through, the victim tries not to be walked
	# through. Nothing the crusher does may clear the victim's view of it.
	var crusher: Commandable = _crusher_without_aggro()
	var victim: Commandable = _entity(VICTIM_PATH, ENEMY, Vector3(1.5, 0, 0))
	victim.set_physics_process(false)

	await _settle_and_update(crusher)
	victim._tick_crush()

	assert_true(_avoids_obstacle_of(victim, crusher),
		"the prey still paths around the thing that would flatten it")
	assert_eq(_agent(victim)._crush_excluded_obstacles, 0,
		"and it excludes nothing of its own — it can crush nothing")
#endregion
