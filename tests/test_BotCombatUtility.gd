extends GutTest

## "UNARMED" IS NOT "USELESS": what the bot counts as a unit that can fight.
##
## `BotMilitary._combat_units` decides both who is re-tasked on a posture change and who the
## idle sweep picks up, so a unit it filters out is a unit no manager claims — it stands
## still for the rest of the match. It used to filter on WEAPONS alone, which discarded the
## Colonial Stock Truck: an empty Loadout, and the piece that runs light infantry over.
##
## These tests pin the rule (armed OR able to crush) rather than any piece, so a new heavy
## vehicle is picked up with no bot change — and pin the one place the rule deliberately does
## NOT apply, `BotScout._applicable_responsibility_count`.


## A Commandable that can live in the tree without a scene behind it — the same shape
## tests/test_BotHostileTargets.gd uses, and for the same reason.
class StubPiece:
	extends Commandable

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


func before_each() -> void:
	_scenario = autofree(Scenario.new()) as Scenario
	_bot = Bot.new()
	_bot.id = 1
	_bot.initialize(null, _scenario)
	add_child_autofree(_bot)
	_scenario.commanders = [_bot]


## An owned unit with the components the rule reads, and nothing else.
func _unit(a_damage: float, a_crush: Movement.CrushClass) -> Commandable:
	var piece: StubPiece = StubPiece.make()
	_bot.add_child(piece)
	piece.ownership.commander = _bot
	if a_damage > 0.0:
		var loadout := autofree(Loadout.new()) as Loadout
		var weapon := Weapon.new()
		weapon.melee_damage = a_damage
		loadout.add_child(weapon)
		piece.weapon_inventory = loadout
	else:
		# The Stock Truck's shape: a Loadout node that holds NO weapon. `!= null` is not the
		# armed test, and mistaking it for one is what this file exists about.
		piece.weapon_inventory = autofree(Loadout.new()) as Loadout
	var movement := autofree(Movement.new()) as Movement
	movement.crush_class = a_crush
	piece.movement = movement
	return piece


func _military() -> BotMilitary:
	return BotMilitary.new(_bot, null)


# ─── THE SENSES ──────────────────────────────────────────────────────────────


func test_a_loadout_with_no_weapon_is_not_armed() -> void:
	assert_false(_bot.unit_is_armed(_unit(0.0, Movement.CrushClass.SMALL)))


func test_a_loadout_with_a_weapon_is_armed() -> void:
	assert_true(_bot.unit_is_armed(_unit(10.0, Movement.CrushClass.SMALL)))


func test_a_small_unit_cannot_crush() -> void:
	assert_false(_bot.unit_can_crush(_unit(0.0, Movement.CrushClass.SMALL)))


func test_a_large_enough_unit_can_crush() -> void:
	# The gap is a size-class comparison on Movement, not a component or a piece id.
	assert_true(_bot.unit_can_crush(_unit(0.0, Movement.CrushClass.LARGE)))


func test_an_unarmed_crusher_has_combat_utility() -> void:
	assert_true(
		_bot.unit_has_combat_utility(_unit(0.0, Movement.CrushClass.LARGE)),
		"the Stock Truck case: no weapon, but it drives over infantry"
	)


func test_an_unarmed_uncrushing_unit_has_no_combat_utility() -> void:
	assert_false(_bot.unit_has_combat_utility(_unit(0.0, Movement.CrushClass.TINY)))


# ─── WHAT THE ARMY CLAIMS ────────────────────────────────────────────────────


func test_the_army_claims_an_unarmed_crusher() -> void:
	var truck: Commandable = _unit(0.0, Movement.CrushClass.LARGE)
	assert_eq(
		_military()._combat_units(_bot.get_units()),
		[truck],
		"nobody else wanted it, and it is not harmless"
	)


func test_the_army_still_leaves_a_genuinely_harmless_unit_alone() -> void:
	_unit(0.0, Movement.CrushClass.TINY)
	assert_eq(
		_military()._combat_units(_bot.get_units()),
		[],
		"a unit with no weapon and no weight is not marched to its death"
	)


func test_the_army_claims_armed_and_crushing_units_together() -> void:
	var soldier: Commandable = _unit(10.0, Movement.CrushClass.SMALL)
	var truck: Commandable = _unit(0.0, Movement.CrushClass.LARGE)
	_unit(0.0, Movement.CrushClass.TINY)
	var claimed: Array = _military()._combat_units(_bot.get_units())
	assert_eq(claimed.size(), 2)
	assert_true(claimed.has(soldier) and claimed.has(truck))


# ─── AND WHERE THE RULE DELIBERATELY DOES NOT APPLY ──────────────────────────


func test_crushing_does_not_make_a_unit_wanted_elsewhere() -> void:
	# BotScout scores a candidate DOWN for every other job that currently wants it, and the
	# Stock Truck is the right opening scout precisely because nothing does. Crushing is
	# damage a unit does wherever it is, not a job that holds it somewhere — so it must not
	# count here even though the army will now take the truck if the scout does not.
	var truck: Commandable = _unit(0.0, Movement.CrushClass.LARGE)
	var soldier: Commandable = _unit(10.0, Movement.CrushClass.SMALL)
	var scout := BotScout.new(_bot, null)
	assert_eq(
		scout._applicable_responsibility_count(truck), 0, "the crusher is nobody's first call"
	)
	assert_eq(scout._applicable_responsibility_count(soldier), 1, "the soldier is the army's")
