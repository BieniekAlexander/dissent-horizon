extends GutTest

## THE KAMIKAZE HOLD IS ENFORCED, NOT ADVISORY.
##
## `BotKamikaze` exists to decide whether spending a drone is worth more than the drone. Its
## hold used to be "walk home", which decides nothing: the drone's own idle aggro picked up
## whatever came into range on the way, so proximity overrode the cost-effectiveness scan the
## module is for — and when the bot owned no structure there was not even a walk home. The
## test that says this must not happen
## (the kamikaze no-cluster simulation scenario) was passing only because fog
## was inert inside GUT and the drone could see nothing at all.
##
## That scenario is the END-TO-END cover, and it is the one that proves the engine-side gate
## (Actor.is_holding_fire) actually stops a pickup. These tests are the unit-level
## half: that the manager sets, clears and enforces the flag at the right moments.


## A Actor with the four children Entity/Actor resolve with a hard `$`, and
## nothing else — same stub shape as tests/test_BotHostileTargets.gd.
class StubPiece:
	extends Actor

	static func make() -> StubPiece:
		var piece := StubPiece.new()
		for pair: Array in [
			["Ownership", Ownership.new()],
			["AvoidanceObstacle", NavigationObstacle3D.new()],
			["Veterancy", Veterancy.new()]
		]:
			var node: Node = pair[1]
			node.name = pair[0]
			piece.add_child(node)
		var bar := Node3D.new()
		bar.name = "HPBar"
		var fill := Sprite3D.new()
		fill.name = "HPBarFill"
		bar.add_child(fill)
		piece.add_child(bar)
		return piece

	func _ready() -> void:
		set_process(false)
		set_physics_process(false)


var _scenario: Scenario
var _bot: Bot
var _kamikaze: BotKamikaze


func before_each() -> void:
	_scenario = autofree(Scenario.new()) as Scenario
	_bot = Bot.new()
	_bot.id = 1
	_bot.initialize(null, _scenario)
	add_child_autofree(_bot)
	_scenario.commanders = [_bot]
	# An actuator with no map: every issuing method returns early, so a command can only get
	# onto a drone here if this test put it there.
	_kamikaze = BotKamikaze.new(_bot, BotActuator.new(null))


func _drone() -> Actor:
	var piece: StubPiece = StubPiece.make()
	_bot.add_child(piece)
	piece.ownership.commander = _bot
	return piece


func test_a_piece_acquires_targets_by_default() -> void:
	assert_false(_drone().is_holding_fire, "the hold is opt-in; nothing else is held")


func test_holding_a_drone_suppresses_its_own_target_acquisition() -> void:
	var drone: Actor = _drone()
	_kamikaze._hold(drone)
	assert_true(
		drone.is_holding_fire,
		"no blast is worth it, so the drone waits rather than taking what is nearest"
	)


func test_holding_drops_an_engagement_aggro_already_committed_to() -> void:
	# Suppression only prevents the NEXT pickup. A drone that has already latched onto
	# something would otherwise fly the run the manager just refused.
	var drone: Actor = _drone()
	var victim: Actor = _drone()
	drone.update_commands(Attack.new(CommandMessage.new(null, victim)))
	assert_true(drone.has_command(), "precondition: it is committed")

	_kamikaze._hold(drone)
	assert_false(drone.has_command(), "the hold calls it off")


func test_holding_leaves_a_drone_with_no_command_at_all() -> void:
	# What the no-cluster scenario asserts, at module level: a held drone with no base to
	# return to stands still and empty-handed rather than being given something to do.
	var drone: Actor = _drone()
	_kamikaze._hold(drone)
	assert_false(drone.has_command())


func test_committing_a_run_releases_the_hold_first() -> void:
	# Or the drone flies in under a hold and cannot re-acquire if the leash ever drops.
	var drone: Actor = _drone()
	var victim: Actor = _drone()
	_kamikaze._hold(drone)
	assert_true(drone.is_holding_fire, "precondition: held")

	_kamikaze._commit(drone, victim)
	assert_false(drone.is_holding_fire, "a committed drone hunts again")
