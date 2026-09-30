extends GutTest

## AGGRO ONLY PICKS FIGHTS WITH WHAT ITS SIDE CAN SEE.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_AggroNeedsVision.gd -gexit
##
## A piece's aggro volume is a raw physics query, so on its own it finds everything inside
## the radius, fogged or not. The vision gate is what makes reach-past-vision pieces
## (artillery) depend on spotters: with it, a target outside the side's vision is not a
## candidate however close it stands. Pinned for both readers of the aggro volume — the
## piece's own idle pickup (Commandable.get_aggro_near_position) and the bot's retreat gate
## (Bot.get_enemies_in_aggro_range). Why: gdd/systems/combat/range-buckets.md §Aggro.
##
## PATHS, not preloads (see CLAUDE.md).

const RECRUIT: Dictionary = {"speed": 2.0, "vision": 8.0, "weapon": {"ground": 6.0}}
const IRREGULAR: Dictionary = {"speed": 2.0, "vision": 8.0}

const SEER: int = 7
const HIDDEN: int = 8


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
	var u: Commandable = FakePieces.unit(a_options)
	add_child_autofree(u)
	u.ownership.commander = a_commander
	u.global_position = a_at
	return u


## A fog for [a_id] with no Map to initialise against: it has revealed nothing, so every
## enemy is out of that commander's vision.
func _blind(a_id: int) -> void:
	var fog := Fog.new()
	fog.watching_commander_id = a_id
	add_child_autofree(fog)


## A recruit for SEER beside an irregular for HIDDEN, well inside the recruit's aggro.
func _pair(a_seer: Commander) -> Array:
	var shooter: Commandable = _unit(RECRUIT, a_seer, Vector3.ZERO)
	var target: Commandable = _unit(IRREGULAR, _commander(HIDDEN), Vector3(2.0, 0.0, 0.0))
	await wait_physics_frames(2)
	return [shooter, target]


func test_a_visible_enemy_in_aggro_is_picked_up() -> void:
	var pair: Array = await _pair(_commander(SEER))
	var cmd: MoveCommand = (pair[0] as Commandable).get_aggro_near_position()
	assert_not_null(cmd, "guards the fixture: no fog, so the enemy is in plain sight")
	assert_eq(cmd.message.target, pair[1])


func test_an_enemy_out_of_vision_is_not_picked_up() -> void:
	var pair: Array = await _pair(_commander(SEER))
	_blind(SEER)
	assert_null((pair[0] as Commandable).get_aggro_near_position(),
		"inside the aggro radius but outside the side's vision: not a candidate")


func test_the_bot_does_not_count_an_enemy_it_cannot_see() -> void:
	var bot: Bot = _commander(SEER, true) as Bot
	var pair: Array = await _pair(bot)
	assert_eq(bot.get_enemies_in_aggro_range(pair[0]), [pair[1]],
		"guards the fixture: no fog, so the bot counts it")
	_blind(SEER)
	assert_eq(bot.get_enemies_in_aggro_range(pair[0]), [],
		"a fogged enemy is not in aggro range for the retreat gate either")
