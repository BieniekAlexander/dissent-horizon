extends GutTest

## HOW FAR A BOT UNIT LOOKS FOR A BETTER TARGET (`BotTargeting._engage_radius`).
##
## It used to be the AGGRO shape alone, and on this content the aggro shapes are authored
## TIGHTER than the weapons — a Badger aggros at 2 world units and shoots at 5. That made a
## self-play match unwinnable: `BotMilitary` marches the army onto the nearest enemy
## structure, the AttackMove completes a few units short of the footprint (a building blocks
## the navmesh it stands on), and nothing — neither idle aggro nor this scan — could see a
## building the army was already in range to destroy. Every unit idled at the foot of the
## enemy base for the rest of the match. See gdd/systems/ai/bot-engagement-fixes.md.
##
## Fixture note: the range SHAPES are parented to the test, not to the unit — the radius is
## read off `global_transform`, which only exists for a node inside the tree, and the units
## themselves stay out of it so no entity wiring has to be faked.

var _bot: Bot
var _targeting: BotTargeting


func before_each() -> void:
	_bot = Bot.new()
	_targeting = BotTargeting.new(_bot, null)


func after_each() -> void:
	_bot.free()


## A cylinder range shape of `a_radius`, in the tree so its transform resolves.
func _shape(a_radius: float) -> CollisionShape3D:
	var node := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = a_radius
	node.shape = cylinder
	add_child_autofree(node)
	return node


## A unit with an aggro shape of `a_aggro` (0 for none) carrying one weapon reaching
## `a_reach` (0 for unarmed).
func _unit(a_aggro: float, a_reach: float) -> Actor:
	var unit: Actor = autofree(Actor.new()) as Actor
	if a_aggro > 0.0:
		unit.aggro_shape_ground = _shape(a_aggro)
	if a_reach > 0.0:
		var loadout := autofree(Loadout.new()) as Loadout
		var weapon := Weapon.new()
		weapon.attack_range_shape_ground = _shape(a_reach)
		loadout.add_child(weapon)
		unit.weapon_inventory = loadout
	return unit


func test_a_unit_scans_as_far_as_it_can_shoot() -> void:
	# The Badger: aggros at 2, shoots at 5. The scan has to be the 5.
	assert_almost_eq(_targeting._engage_radius(_unit(2.0, 5.0)), 5.0, 0.001)


func test_a_wider_aggro_shape_still_wins() -> void:
	# REACH is a floor, not a replacement: a unit that notices trouble further out than it
	# can shoot keeps looking that far.
	assert_almost_eq(_targeting._engage_radius(_unit(9.0, 5.0)), 9.0, 0.001)


func test_an_unarmed_unit_falls_back_to_its_aggro_shape() -> void:
	assert_almost_eq(_targeting._engage_radius(_unit(3.0, 0.0)), 3.0, 0.001)


func test_a_unit_with_neither_gets_the_configured_scan_radius() -> void:
	_targeting.scan_radius = 7.0
	assert_almost_eq(_targeting._engage_radius(_unit(0.0, 0.0)), 7.0, 0.001)


func test_the_longest_weapon_is_the_one_that_counts() -> void:
	var unit: Actor = _unit(1.0, 4.0)
	var sniper := Weapon.new()
	sniper.attack_range_shape_ground = _shape(11.0)
	unit.weapon_inventory.add_child(sniper)
	assert_almost_eq(_targeting._engage_radius(unit), 11.0, 0.001)
