extends GutTest

## A FLYING unit reaching its destination and settling into its idle loiter, driven through
## the REAL command loop (CommandReceiver → Movement) rather than by poking Movement.
##
## This is here because the unit-level tests missed the bug twice. Driving
## compute_orbit_velocity() by hand never reproduced it: the failure only appears when the
## unit ARRIVES at full travel speed and has to shed it against bounded deceleration, which
## is a property of the command loop, not of the orbit maths. The symptom was the unit
## turning one way, then back the other, before settling — twice, visibly.
##
## The measure is STRAIGHTNESS: |net turning| / |total turning| over the post-arrival run.
## A clean entry sweeps one way and keeps going round, giving ~1.0. Turning out and back
## drives it toward 0 no matter how far round the circle the sample happens to reach, which
## is what makes it a fair metric here (a unit in a steady orbit is always turning).

## THE SCENARIO IS BORROWED AS A FLYING-UNIT HARNESS, and this test therefore empties it.
## Nothing here is about the kamikaze: it wants one aerial unit, a map, and no interference.
## Once fog started working inside GUT the drone acquired a victim and detonated before the
## orbit could be observed, and the test read a freed node — not a regression in orbit entry
## but a fixture that had been relying on the bot being blind
## (gdd/systems/ai/bot-engagement-fixes.md §What this broke). So the enemies are dropped and
## the brains are switched off, and the only thing left in the scene is the unit under test.

const SCENE: String = "res://scenes/scenarios/test/test_kamikaze_cluster.tscn"
const BOOT_TICKS: int = 30
## Long enough to cover the whole entry transient (~2s) plus a stretch of settled orbit.
const OBSERVE_TICKS: int = 150


func _find_drone() -> Actor:
	for node: Node in get_tree().get_nodes_in_group("unit"):
		var c := node as Actor
		if c != null and c.id == EntityIds.AN_AIRCRAFT_LIGHT_ANTI_MECH:
			return c
	return null


func test_flying_unit_settles_into_its_orbit_without_doubling_back() -> void:
	gut.error_tracker.disabled = true
	var scenario := (load(SCENE) as PackedScene).instantiate() as SimulationScenario
	add_child_autofree(scenario)
	# Emptied BEFORE boot: the drone spawns inside aggro of the cluster and would otherwise
	# dive on it and detonate inside the boot window.
	var drone: Actor = _find_drone()
	assert_not_null(drone, "the scenario provides a FLYING unit")
	if drone == null:
		gut.error_tracker.disabled = false
		return
	_empty_the_harness(scenario, drone)
	for i in BOOT_TICKS:
		await get_tree().physics_frame

	# Far enough that it is at full travel speed on arrival — which is the whole point.
	var dest: Vector3 = drone.global_position + Vector3(12.0, 0.0, 0.0)
	drone.update_commands(MoveCommand.new(CommandMessage.new(drone.map, null, null, dest)))

	var arrived: bool = false
	var prev_yaw: float = drone.rotation.y
	var total: float = 0.0
	var net: float = 0.0
	var observed: int = 0
	var max_radius: float = 0.0
	for i in 400:
		await get_tree().physics_frame
		if not is_instance_valid(drone):
			break
		var d: float = angle_difference(prev_yaw, drone.rotation.y)
		prev_yaw = drone.rotation.y
		if not arrived:
			arrived = not drone.has_command()
			continue
		total += absf(d)
		net += d
		max_radius = maxf(
			max_radius, VU.in_xz(drone.global_position).distance_to(VU.in_xz(drone.aerial._anchor))
		)
		observed += 1
		if observed >= OBSERVE_TICKS:
			break
	gut.error_tracker.disabled = false

	assert_true(arrived, "the unit reached its destination and went idle")
	assert_gt(total, deg_to_rad(90.0), "precondition: it actually manoeuvred after arriving")
	var straightness: float = absf(net) / total if total > 1e-6 else 1.0
	assert_gt(
		straightness,
		0.95,
		(
			(
				"settles into the orbit turning one way throughout (straightness %.2f; below ~0.8 "
				% straightness
			)
			+ "means it turned out and back before settling)"
		)
	)
	# It may overshoot the radius slightly while shedding approach speed, but it must not
	# sail far past and get hauled back — that excursion is the other half of the wobble.
	assert_lt(
		max_radius,
		drone.aerial.orbit_radius * 1.25,
		(
			"never sails far outside its orbit radius (peak %.2f vs radius %.2f)"
			% [max_radius, drone.aerial.orbit_radius]
		)
	)


## Leave `a_keep` alone in the world: every other commandable freed, every brain silenced.
## A flying unit's approach and loiter are what is under test, and both a target to dive at
## and an order from a bot would replace the thing being measured.
func _empty_the_harness(a_scenario: Scenario, a_keep: Actor) -> void:
	for commander: Commander in a_scenario.commanders:
		var brain := commander.get_node_or_null("BotBrain") as BotBrain
		if brain != null:
			brain.active = false
	for node: Node in get_tree().get_nodes_in_group("piece"):
		if node != a_keep and node is Actor:
			node.queue_free()
