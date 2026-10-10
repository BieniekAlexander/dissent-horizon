extends GutTest

## THE GUN'S OWN SHOT: a loaded Bombard fires at the most valuable visible enemy standing on
## ground its side spots, never with one of ours under the blast, and never at ground nobody
## spots — the bot's half of the siege loop where no held beacon calls the shot
## (gdd/systems/ai/bot-architecture.md §Local abilities).

const GUN: StringName = &"fake_gun"
const BLAST: float = 3.0
const SPOTTING_RADIUS: float = 20.0


## Sees exactly the enemies the test places and prices them by id.
class FakeBot:
	extends Bot
	var own: Array = []
	var structures: Array = []
	var enemies: Array = []
	var costs: Dictionary = {}

	func get_units() -> Array:
		return own

	func get_structures() -> Array:
		return structures

	func visible_enemies() -> Array:
		return enemies

	func unit_cost(a_unit_type) -> int:
		return int(costs.get(a_unit_type, 100))


## Records the shot and leaves the gun holding it, as the real order would.
class RecordingActuator:
	extends BotActuator
	var shots: Array = []  # [{"gun", "at"}]

	func bombard(a_gun: Actor, a_world_pos: Vector3) -> bool:
		shots.append({"gun": a_gun, "at": a_world_pos})
		a_gun.update_commands(
			Bombard.new(CommandMessage.new(null, null, null, a_world_pos, Bombard.ABILITY_ID))
		)
		return true


var _bot: FakeBot
var _act: RecordingActuator
var _abilities: BotAbilities


func before_each() -> void:
	FakePieces.install_ability(GUN, {"command": "command_bombard"})
	AbilityCatalog._blast_radius_cache[Bombard.ABILITY_ID] = BLAST
	_bot = FakeBot.new()
	_bot.id = 1
	add_child_autofree(_bot)
	_act = RecordingActuator.new(null)
	_abilities = BotAbilities.new(_bot, _act)


func after_each() -> void:
	FakePieces.restore_abilities()
	AbilityCatalog._blast_radius_cache.erase(Bombard.ABILITY_ID)


## A loaded gun that spots its own surroundings, as the Bombard does. A child of the bot:
## BombardTargeting reads spotting off the commander's own pieces.
func _loaded_gun() -> Actor:
	var gun: Actor = FakePieces.structure(
		{"abilities": [{"grants": [GUN]}], "beacon_range": SPOTTING_RADIUS}
	)
	_bot.add_child(gun)
	gun.ownership.commander = _bot
	_bot.structures.append(gun)
	return gun


func _enemy(a_id: StringName, a_at: Vector3, a_cost: int) -> Actor:
	var piece: Actor = FakePieces.unit({"id": a_id})
	add_child_autofree(piece)
	piece.global_position = a_at
	_bot.enemies.append(piece)
	_bot.costs[a_id] = a_cost
	return piece


func _friend(a_at: Vector3) -> Actor:
	var piece: Actor = FakePieces.unit({})
	add_child_autofree(piece)
	piece.ownership.commander = _bot
	piece.global_position = a_at
	_bot.own.append(piece)
	return piece


func test_a_loaded_gun_fires_at_the_most_valuable_spotted_enemy() -> void:
	var gun: Actor = _loaded_gun()
	_enemy(&"cheap", Vector3(5.0, 0.0, 0.0), 100)
	var dear: Actor = _enemy(&"dear", Vector3(-10.0, 0.0, 0.0), 1000)
	_abilities.tick()
	assert_eq(_act.shots.size(), 1, "one shell")
	assert_eq(_act.shots[0]["gun"], gun)
	assert_eq(_act.shots[0]["at"], dear.global_position, "the dear one, inside the gun's bubble")


func test_a_clump_outweighs_a_single_dearer_piece() -> void:
	_loaded_gun()
	_enemy(&"a", Vector3(5.0, 0.0, 0.0), 400)
	_enemy(&"b", Vector3(6.0, 0.0, 0.0), 400)
	_enemy(&"dear", Vector3(-10.0, 0.0, 0.0), 700)
	_abilities.tick()
	assert_eq(_act.shots.size(), 1)
	assert_almost_eq(
		(_act.shots[0]["at"] as Vector3).x, 5.0, 0.001, "800 under one blast beats 700"
	)


func test_ground_nobody_spots_is_not_fired_on() -> void:
	_loaded_gun()
	_enemy(&"far", Vector3(SPOTTING_RADIUS + 10.0, 0.0, 0.0), 1000)
	_abilities.tick()
	assert_eq(_act.shots, [], "no eyes on that ground")


func test_a_shot_with_one_of_ours_under_it_is_not_fired() -> void:
	_loaded_gun()
	_enemy(&"dear", Vector3(-10.0, 0.0, 0.0), 1000)
	_friend(Vector3(-10.0, 0.0, 1.0))
	_abilities.tick()
	assert_eq(_act.shots, [], "the shell does not take sides")


func test_a_gun_already_ordered_to_fire_is_not_ordered_again() -> void:
	_loaded_gun()
	_enemy(&"dear", Vector3(-10.0, 0.0, 0.0), 1000)
	_abilities.tick()
	_abilities.tick()
	assert_eq(_act.shots.size(), 1, "one order per charge")


func test_an_unfinished_gun_fires_nothing() -> void:
	var gun: Actor = _loaded_gun()
	gun.build_progress = 0.5
	_enemy(&"dear", Vector3(-10.0, 0.0, 0.0), 1000)
	_abilities.tick()
	assert_eq(_act.shots, [])
