extends GutTest

## How the managers respect BotClaims. With every manager on its own period, "the scout ran
## before the military" is no longer something the code can rely on; these tests pin that the
## claim alone keeps a unit where its owner put it.


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


## Records orders instead of issuing them, so no map is needed.
class RecordingActuator:
	extends BotActuator
	var moved: Array = []

	func move(a_units: Array, _a_world_pos: Vector3) -> void:
		moved.append_array(a_units)


var _scenario: Scenario
var _bot: Bot
var _claims: BotClaims


func before_each() -> void:
	_scenario = autofree(Scenario.new()) as Scenario
	_bot = Bot.new()
	_bot.id = 1
	_bot.initialize(null, _scenario)
	add_child_autofree(_bot)
	_scenario.commanders = [_bot]
	_claims = BotClaims.new()


func _armed_unit() -> Actor:
	var piece: StubPiece = StubPiece.make()
	_bot.add_child(piece)
	piece.ownership.commander = _bot
	var loadout := autofree(Loadout.new()) as Loadout
	var weapon := Weapon.new()
	weapon.melee_damage = 10.0
	loadout.add_child(weapon)
	piece.weapon_inventory = loadout
	var movement := autofree(Movement.new()) as Movement
	piece.movement = movement
	return piece


func test_the_army_leaves_a_claimed_unit_alone() -> void:
	var free_unit := _armed_unit()
	var scout := _armed_unit()
	_claims.claim(scout, BotScout.CLAIM_OWNER, BotClaims.Priority.SCOUT)
	var military := BotMilitary.new(_bot, null)
	military.claims = _claims
	assert_eq(
		military._combat_units(_bot.get_units()),
		[free_unit],
		"a scout is not swept into the rally, whichever manager ran first"
	)


func test_a_scout_taken_by_a_stronger_claim_is_given_up() -> void:
	var unit := _armed_unit()
	var scout := BotScout.new(_bot, null)
	scout.claims = _claims
	scout._scouts = [unit]
	_claims.claim(unit, BotTargeting.CLAIM_OWNER, BotClaims.Priority.COMBAT)
	scout._update_scouts()
	assert_false(scout._scouts.has(unit), "the fight has it now")
	assert_true(_claims.owns(unit, BotTargeting.CLAIM_OWNER), "and the scout did not take it back")


func test_a_scout_still_held_is_claimed_for_scouting() -> void:
	var unit := _armed_unit()
	var scout := BotScout.new(_bot, RecordingActuator.new(null))
	scout.claims = _claims
	scout.unit_budget = 1
	scout._scouts = [unit]
	# Fully blind, so keeping the one scout out pays for itself.
	for i: int in 10:
		scout._scout_grid[Vector2i(i, 0)] = -INF
		scout._scout_grid_positions[Vector2i(i, 0)] = Vector3(i * BotFields.PITCH, 0, 0)
	scout._update_scouts()
	assert_true(_claims.owns(unit, BotScout.CLAIM_OWNER))


func test_the_scout_does_not_draft_a_unit_on_an_errand() -> void:
	var unit := _armed_unit()
	_claims.claim(unit, BotEconomy.CLAIM_OWNER, BotClaims.Priority.ERRAND)
	var scout := BotScout.new(_bot, null)
	scout.claims = _claims
	for i: int in 10:
		scout._scout_grid[Vector2i(i, 0)] = -INF
	assert_eq(scout._pick_scout(), null)


func test_targeting_releases_a_unit_whose_engagement_is_over() -> void:
	var unit := _armed_unit()
	var targeting := BotTargeting.new(_bot, null)
	targeting.claims = _claims
	_claims.claim(unit, BotTargeting.CLAIM_OWNER, BotClaims.Priority.COMBAT)
	targeting._release_finished_engagements()  # it holds no Attack
	assert_false(_claims.is_claimed(unit), "back to the army")


func test_a_kamikaze_drone_is_claimed_exclusively() -> void:
	var unit := _armed_unit()
	_claims.claim(unit, BotKamikaze.CLAIM_OWNER, BotClaims.Priority.EXCLUSIVE)
	assert_false(_claims.can_claim(unit, BotOpportunist.CLAIM_OWNER, BotClaims.Priority.ERRAND))
	assert_false(_claims.can_claim(unit, BotTargeting.CLAIM_OWNER, BotClaims.Priority.COMBAT))
