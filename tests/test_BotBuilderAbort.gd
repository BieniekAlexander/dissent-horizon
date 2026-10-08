extends GutTest

## A BUILDER IS NOT SENT INTO A DEFENDED SITE, AND IS CALLED BACK FROM ONE. Until 2026-10-07
## the only abort was an enemy standing ON the footprint, so a lone Servant walked into a
## contested extraction site and died (observed on main). BotEconomy now reads the visible
## armed enemies near a site — the same `defend_threat_radius` every manager calls "under
## threat" — before issuing and on every think while the walk lasts, and remembers the spot
## as contested for a cooldown (BotEconomy.CONTESTED_SPOT_SECONDS).


class StubPiece:
	extends Actor

	static func make() -> StubPiece:
		var piece := StubPiece.new()
		for pair: Array in [
			["Ownership", Ownership.new()],
			["AvoidanceObstacle", NavigationObstacle3D.new()],
			["Veterancy", Veterancy.new()],
			["Orders", Orders.new()]
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
		command_receiver.initialize(self)


## Sees exactly the enemies the test places, each armed unless named "unarmed".
class FakeBot:
	extends Bot
	var enemies: Array = []  # [{"at": Vector3, "piece": Actor}]
	var own: Array = []
	var now: float = 0.0

	func seconds_elapsed() -> float:
		return now

	func get_units() -> Array:
		return own

	func visible_enemies_near(a_position: Vector3, a_radius: float) -> Array:
		var out: Array = []
		for entry: Dictionary in enemies:
			if (entry["at"] as Vector3).distance_to(a_position) <= a_radius:
				out.append(entry["piece"])
		return out

	func unit_can_attack(a_type) -> bool:
		return a_type != &"unarmed"


const SITE: Vector3 = Vector3(40.0, 0.0, 0.0)

var _bot: FakeBot
var _economy: BotEconomy


func before_each() -> void:
	_bot = FakeBot.new()
	_bot.id = 1
	add_child_autofree(_bot)
	_economy = BotEconomy.new(_bot, BotActuator.new(null))
	_economy.defend_threat_radius = 10.0


func _builder_walking_to(a_site: Vector3) -> Actor:
	var piece: StubPiece = StubPiece.make()
	_bot.add_child(piece)
	piece.ownership.commander = _bot
	piece.update_commands(Build.new(CommandMessage.new(null, null, null, a_site)))
	_economy.claims.claim(piece, BotEconomy.CLAIM_OWNER, BotClaims.Priority.ERRAND)
	_bot.own.append(piece)
	return piece


func _enemy_at(a_at: Vector3, a_type: StringName = &"trooper") -> void:
	var piece: Actor = autofree(Actor.new())
	piece.id = a_type
	_bot.enemies.append({"at": a_at, "piece": piece})


func test_a_builder_walking_into_a_defended_site_is_called_back() -> void:
	var builder: Actor = _builder_walking_to(SITE)
	_enemy_at(SITE + Vector3(5.0, 0.0, 0.0))
	_economy._abort_contested_jobs()
	assert_false(builder.has_command(), "the order is dropped before it arrives")
	assert_false(_economy.claims.is_claimed(builder), "and the army may have it back")


func test_an_unarmed_enemy_near_the_site_is_no_reason_to_turn_back() -> void:
	var builder: Actor = _builder_walking_to(SITE)
	_enemy_at(SITE + Vector3(5.0, 0.0, 0.0), &"unarmed")
	_economy._abort_contested_jobs()
	assert_true(builder.has_command(), "a scout cannot kill a builder")


func test_an_enemy_beyond_the_threat_radius_is_not_near() -> void:
	var builder: Actor = _builder_walking_to(SITE)
	_enemy_at(SITE + Vector3(25.0, 0.0, 0.0))
	_economy._abort_contested_jobs()
	assert_true(builder.has_command())


func test_a_contested_spot_is_skipped_for_the_cooldown_and_then_tried_again() -> void:
	_builder_walking_to(SITE)
	_enemy_at(SITE + Vector3(5.0, 0.0, 0.0))
	_economy._abort_contested_jobs()
	_bot.enemies.clear()  # the enemy has moved on; the memory has not
	assert_true(_economy._is_contested_spot(SITE), "remembered")
	assert_true(_economy._is_contested_spot(SITE + Vector3(3.0, 0.0, 0.0)), "and its surrounds")
	_bot.now += BotEconomy.CONTESTED_SPOT_SECONDS + 1.0
	assert_false(_economy._is_contested_spot(SITE), "a cooldown, not a ban")


func test_a_site_an_enemy_stands_over_is_contested_before_anyone_is_sent() -> void:
	_enemy_at(SITE + Vector3(5.0, 0.0, 0.0))
	assert_true(_economy._is_contested_spot(SITE), "read live, no memory needed")
