extends GutTest

## AGGRO ASKS THE PHYSICS QUERY FOR HOSTILES ONLY.
##
## Run with:
## godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_AggroIgnoresAllies.gd -gexit
##
## The aggro query is capped (Commandable.AGGRO_SCAN_MAX_RESULTS) before any script filter
## runs, and a physics query is not nearest-first, so when it returned allies too a crowd of
## friendly bodies could fill the cap and hide an enemy standing in plain sight. Each
## TargetBody now carries a per-side bit, and the query masks out the asker's own side and
## neutral. Why: gdd/systems/combat/target-acquisition.md §Aggro filters allegiance.
##
## PATHS, not preloads (see CLAUDE.md).

const RECRUIT: Dictionary = FakePieces.SOLDIER
const IRREGULAR: Dictionary = FakePieces.BUILDER
const GROUND: int = CollisionLayers.Mask.TARGETABLE_GROUND
const AIR: int = CollisionLayers.Mask.TARGETABLE_AIR

const OWN: int = 1
const FOE: int = 2
## More allies than the scan considers, so an unfiltered query could return nothing else.
const ALLY_COUNT: int = 16


func before_each() -> void:
	Fog._fogs_by_commander.clear()


func after_each() -> void:
	Fog._fogs_by_commander.clear()


func _commander(a_id: int, a_bot: bool = false) -> Commander:
	var c: Commander = Bot.new() if a_bot else Commander.new()
	c.id = a_id
	add_child_autofree(c)
	return c


func _unit(a_options: Dictionary, a_commander: Commander, a_at: Vector3) -> Commandable:
	var u := FakePieces.make(a_options) as Commandable
	add_child_autofree(u)
	u.ownership.commander = a_commander
	u.global_position = a_at
	return u


## A shooter ringed by ALLY_COUNT allies closer than the one enemy. The enemy is created
## FIRST: the physics query lists bodies newest-first, so an unfiltered scan capped at
## AGGRO_SCAN_MAX_RESULTS returns only allies — the failure this file pins.
func _crowd(a_own: Commander) -> Array:
	var enemy: Commandable = _unit(IRREGULAR, _commander(FOE), Vector3(3.0, 0.0, 0.0))
	var shooter: Commandable = _unit(RECRUIT, a_own, Vector3.ZERO)
	for i: int in ALLY_COUNT:
		var angle: float = TAU * i / ALLY_COUNT
		_unit(RECRUIT, a_own, Vector3(cos(angle), 0.0, sin(angle)) * 1.5)
	await wait_physics_frames(2)
	return [shooter, enemy]


func test_side_bits_sit_clear_of_every_other_layer() -> void:
	var sides: int = CollisionLayers.all_side_bits(CollisionLayers.TARGETABLE_ANY)
	var named: int = 0
	for key: String in CollisionLayers.Mask.keys():
		named |= int(CollisionLayers.Mask[key])
	assert_eq(sides & named, 0, "a side bit must not alias a named layer")
	assert_eq(CollisionLayers.all_side_bits(GROUND) & CollisionLayers.all_side_bits(AIR), 0)
	assert_eq(sides >> 32, 0, "Godot has 32 physics layers")


func test_hostile_mask_is_every_side_but_the_askers_own() -> void:
	for id: int in range(1, Commander.NUM_MAX_COMMANDERS + 1):
		for layer: int in [GROUND, AIR]:
			var mask: int = CollisionLayers.hostile_mask(layer, id)
			assert_eq(mask & CollisionLayers.side_bits(layer, id), 0, "own side excluded")
			for other: int in range(1, Commander.NUM_MAX_COMMANDERS + 1):
				if other != id:
					assert_ne(
						mask & CollisionLayers.side_bits(layer, other),
						0,
						"side %d is hostile to %d" % [other, id]
					)


func test_neutral_has_no_side() -> void:
	assert_eq(CollisionLayers.side_bits(CollisionLayers.TARGETABLE_ANY, 0), 0)


func test_a_target_body_carries_its_owners_side_and_follows_a_capture() -> void:
	var unit: Commandable = _unit(RECRUIT, _commander(OWN), Vector3.ZERO)
	var layer: int = unit.target_body.collision_layer
	assert_ne(layer & CollisionLayers.side_bits(GROUND, OWN), 0)
	assert_eq(unit.targetable_layers(), GROUND, "the generic bits are unchanged")
	unit.ownership.commander = _commander(FOE)
	layer = unit.target_body.collision_layer
	assert_eq(layer & CollisionLayers.side_bits(GROUND, OWN), 0, "old side dropped")
	assert_ne(layer & CollisionLayers.side_bits(GROUND, FOE), 0, "new side taken")


func test_allies_never_fill_the_aggro_scan() -> void:
	var pair: Array = await _crowd(_commander(OWN))
	var shooter: Commandable = pair[0]
	var found: Array[Entity] = shooter.hostiles_in_aggro(Commandable.AGGRO_SCAN_MAX_RESULTS)
	assert_eq(found.size(), 1, "no ally comes back from the query")
	assert_true(found.has(pair[1]))
	var cmd: MoveCommand = shooter.get_aggro_near_position()
	assert_not_null(cmd, "the enemy is found through the crowd")
	assert_eq(cmd.message.target, pair[1])


func test_a_caller_supplied_region_ignores_allies_too() -> void:
	var pair: Array = await _crowd(_commander(OWN))
	var shooter: Commandable = pair[0]
	var cmd: MoveCommand = shooter.get_aggro_near_position(null, shooter.aggro_shape_ground)
	assert_not_null(cmd)
	assert_eq(cmd.message.target, pair[1])


func test_the_bot_counts_the_enemy_through_the_crowd() -> void:
	var bot: Bot = _commander(OWN, true) as Bot
	var pair: Array = await _crowd(bot)
	var enemies: Array = bot.get_enemies_in_aggro_range(pair[0])
	assert_eq(enemies.size(), 1)
	assert_true(enemies.has(pair[1]))
