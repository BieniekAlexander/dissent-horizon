extends GutTest

## End-to-end cover for the kamikaze's suicide run: order the drone onto a target and
## assert it actually fires its bomb AND dies to it.
##
## Worth an explicit test because the mechanic is load-bearing on geometry that nothing
## else enforces. SuicideStatusEffect kills the projectile's FIRER, but EffectApplicator
## skips application entirely when the blast catches nobody — so the drone only dies if
## its bomb lands on at least one recipient. SuicideStatusEffect's own docstring flags
## this ("if that geometry changes, this effect can silently stop firing"), and a silent
## failure here looks like a drone that attacks forever without detonating rather than
## like an error. These assertions turn that into a red test.
##
## Boots the real game via the authored kamikaze scenario, then issues the Attack
## directly rather than waiting for the bot, so the test exercises the weapon/projectile/
## effect chain rather than the bot's target selection (which the kamikaze simulation
## scenarios cover).
##
## THE SCENARIO IS A HARNESS AND THIS TEST SHAPES ITS OWN FIXTURE. Both bot brains are
## switched off and the drone is started AWAY from the cluster, and both are about making the
## dive the only thing under test. With live fog the brains act: the owning bot's
## BotKamikaze holds or re-targets the drone the test just ordered, and the far commander
## moves its units, so the geometry the last assertion measures shifts under it. That is what
## turned this into a knife-edge (`altitude 0.50 <= reach 0.50`) and then a red test the
## moment fog started working inside GUT — see gdd/systems/ai/bot-engagement-fixes.md
## §What this broke.

const SCENE: String = "res://scenes/scenarios/test/test_kamikaze_cluster.tscn"

## Ticks to let the scenario finish booting (navmesh sync, auto-initialize).
const BOOT_TICKS: int = 30
## Ticks to wait for the whole fire → detonate → suicide chain, including the approach.
const RUN_TICKS: int = 450
## How far from its victim the drone starts, in world units. Far enough that it has to FLY
## there and shed cruise altitude on arrival — which is the point of the altitude assertion.
## Parking it 0.2 units away instead meant it was already inside the AttackRange cylinder at
## cruise height, so the assertion was decided by a fraction of a unit of drift.
const APPROACH_DISTANCE: float = 6.0


func _find_units() -> Dictionary:
	var kamikaze: Commandable = null
	var victim: Commandable = null
	for node: Node in get_tree().get_nodes_in_group("unit"):
		var c := node as Commandable
		if c == null:
			continue
		if c.id == EntityIds.AN_AIRCRAFT_LIGHT_ANTI_MECH:
			kamikaze = c
		elif victim == null and c.commander_id != 1:
			victim = c
	return {"kamikaze": kamikaze, "victim": victim}


func test_kamikaze_detonates_and_dies_to_its_own_blast() -> void:
	# The scenario boots a live Map; Godot 4.7 logs benign NavigationServer
	# "before first synchronization" noise while the nav map first syncs.
	gut.error_tracker.disabled = true
	var scenario := (load(SCENE) as PackedScene).instantiate() as SimulationScenario
	add_child_autofree(scenario)
	# The fixture, not the scenario, and it takes hold BEFORE boot: nothing may issue an order
	# to either side, or the drone is re-tasked and the victims walk out from under the bomb —
	# and the drone spawns inside aggro of the cluster, so left to itself it latches on and
	# detonates within the boot window. The Attack below releases the hold.
	_silence_brains(scenario)
	var spawned_drone: Commandable = _find_units()["kamikaze"]
	if spawned_drone != null:
		spawned_drone.is_holding_fire = true
	for i in BOOT_TICKS:
		await get_tree().physics_frame

	var units: Dictionary = _find_units()
	var kamikaze: Commandable = units["kamikaze"]
	var victim: Commandable = units["victim"]
	assert_not_null(kamikaze, "the scenario provides a kamikaze")
	assert_not_null(victim, "the scenario provides an enemy target")
	if kamikaze == null or victim == null:
		gut.error_tracker.disabled = false
		return

	# Start it a real distance away so the run is an APPROACH and a dive rather than a
	# detonation from where it already stands.
	kamikaze.global_position = victim.global_position + Vector3(APPROACH_DISTANCE, 0.0, 0.0)
	await get_tree().physics_frame

	var msg := CommandMessage.new(kamikaze.map, victim, null, victim.global_position)
	msg.persist = true
	kamikaze.update_commands(Attack.new(msg))

	var reach: float = kamikaze.weapon_inventory.get_weapons()[0].reach_for(victim)
	var fired: bool = false
	var died_at: int = -1
	## The altitude the drone was at when it committed.
	##
	## Sampled ONE TICK BEHIND the bomb's first appearance, and that is not a fudge. The bomb
	## exists at the END of the frame the weapon fired in, by which point Movement has already
	## begun easing the drone back up (request_dive self-clears once the run resolves), so the
	## altitude read on the frame the projectile is first VISIBLE is the altitude the drone had
	## climbed to afterwards — not the one it fired from. The old reading was a frame late and
	## landed on the boundary exactly (0.50 <= 0.50), which is what made the assertion a
	## knife edge rather than a measurement.
	var altitude_at_launch: float = -1.0
	var previous_altitude: float = kamikaze.aerial.height_offset()
	for i in RUN_TICKS:
		if not is_instance_valid(kamikaze):
			died_at = i
			break
		if not fired and _live_projectile_count(kamikaze.commander) > 0:
			fired = true
			altitude_at_launch = previous_altitude
		previous_altitude = kamikaze.aerial.height_offset()
		await get_tree().physics_frame
	gut.error_tracker.disabled = false

	assert_true(fired, "the drone actually fired its bomb")
	assert_true(died_at >= 0,
		"the drone died to its own blast within %d ticks (still alive = the blast caught " % RUN_TICKS
		+ "nobody, so SuicideStatusEffect never ran)")
	# The point of the dive rework: a ramming attack has to happen ON the target, not six
	# units above it. Every AttackRange is a 100-tall cylinder, so the range check alone
	# said "in range" from cruise altitude and the drone detonated in mid-air.
	assert_true(altitude_at_launch >= 0.0 and altitude_at_launch <= reach,
		"detonated in contact (altitude %.2f <= reach %.2f), not from cruise altitude"
			% [altitude_at_launch, reach])


## Emissions currently alive under `a_root`. Bombs are parented to the FIRING COMMANDER,
## and this is asked of the drone's commander alone rather than of the whole scenario for
## that reason: scanning the scenario counted the defenders' return fire too, and their first
## bullet arrives while the drone is still on its way in — so "the drone has fired" read true
## several ticks early and the altitude sample was taken mid-approach.
func _live_projectile_count(a_root: Node) -> int:
	var count: int = 0
	var stack: Array[Node] = [a_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Entity and Payload.of(n) != null:
			count += 1
		for c: Node in n.get_children():
			stack.append(c)
	return count


## Switch off every BotBrain in the scenario. The bot's own decisions are covered by
## the simulation scenarios; here they are interference.
func _silence_brains(a_scenario: Scenario) -> void:
	for commander: Commander in a_scenario.commanders:
		var brain := commander.get_node_or_null("BotBrain") as BotBrain
		if brain != null:
			brain.active = false

