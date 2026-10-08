extends GutTest

## THE BOT CASTS ITS PIECES' LOCAL ABILITIES: a strike at a clump of visible enemies within
## reach, never under its own units; and a spotter sent to call a solution in for a loaded
## gun, one per gun (gdd/systems/ai/bot-architecture.md §Local abilities). The abilities are
## installed by the test — what a strike is and what a spot is are read off `command:`, and
## no shipped id is named.

const STRIKE: StringName = &"fake_strike"
const SPOT: StringName = &"spot"  # Spot.ABILITY_ID: the command keys on it
const PASSIVE: StringName = &"fake_passive"
const STRIKE_REACH: float = 5.0
const BLAST: float = 2.0


## Sees exactly the enemies the test places; believes the structure the test says.
class FakeBot:
	extends Bot
	var own: Array = []
	var structures: Array = []
	var enemies: Array = []
	var believed_at: Variant = null

	func get_units() -> Array:
		return own

	func get_structures() -> Array:
		return structures

	func visible_enemies_near(a_position: Vector3, a_radius: float) -> Array:
		return enemies.filter(
			func(e: Actor) -> bool:
				return e.global_position.distance_to(a_position) <= a_radius
		)

	func nearest_believed_enemy_structure_entry(
		_a_accept: Variant = null
	) -> CommanderBlackboard.Entry:
		if believed_at == null:
			return null
		var entry := CommanderBlackboard.Entry.new()
		entry.last_known_location = believed_at
		entry.is_structure = true
		return entry

	func is_reachable(_a_from: Vector3, _a_to: Vector3, _a_tolerance: float) -> bool:
		return true


class RecordingActuator:
	extends BotActuator
	var casts: Array = []  # [{"caster", "id", "at"}]
	var spots: Array = []  # [{"spotter", "at"}]

	func use_ability(a_caster: Actor, a_ability_id: StringName, a_world_pos: Vector3) -> bool:
		casts.append({"caster": a_caster, "id": a_ability_id, "at": a_world_pos})
		return true

	func spot(a_spotter: Actor, a_world_pos: Vector3) -> bool:
		spots.append({"spotter": a_spotter, "at": a_world_pos})
		# A real order leaves the spotter holding a Spot; the release test reads that.
		a_spotter.update_commands(Spot.new(CommandMessage.new(null, null, null, a_world_pos)))
		return true


var _bot: FakeBot
var _act: RecordingActuator
var _abilities: BotAbilities


func before_each() -> void:
	FakePieces.install_ability(STRIKE, {"command": "command_launch", "range": STRIKE_REACH})
	FakePieces.install_ability(SPOT, {"command": "command_spot", "range": 10.0})
	FakePieces.install_ability(PASSIVE, {"command": "command_launch", "passive": true})
	FakePieces.install_ability(&"fake_gun", {"command": "command_bombard"})
	AbilityCatalog._blast_radius_cache[STRIKE] = BLAST
	_bot = FakeBot.new()
	_bot.id = 1
	add_child_autofree(_bot)
	_act = RecordingActuator.new(null)
	_abilities = BotAbilities.new(_bot, _act)


func after_each() -> void:
	FakePieces.restore_abilities()
	AbilityCatalog._blast_radius_cache.erase(STRIKE)


func _caster(a_grants: Array, a_at: Vector3 = Vector3.ZERO) -> Actor:
	var piece: Actor = FakePieces.unit({"abilities": [{"grants": a_grants}]})
	add_child_autofree(piece)
	piece.ownership.commander = _bot
	piece.global_position = a_at
	_bot.own.append(piece)
	return piece


func _enemy(a_at: Vector3) -> Actor:
	var piece: Actor = FakePieces.unit({})
	add_child_autofree(piece)
	piece.global_position = a_at
	_bot.enemies.append(piece)
	return piece


func _loaded_gun() -> Actor:
	var gun: Actor = FakePieces.structure({"abilities": [{"grants": [&"fake_gun"]}]})
	add_child_autofree(gun)
	gun.ownership.commander = _bot
	_bot.structures.append(gun)
	return gun


# ─── STRIKES ─────────────────────────────────────────────────────────────────


func test_a_clump_of_enemies_in_reach_is_struck_at_its_centre() -> void:
	var caster: Actor = _caster([STRIKE])
	_enemy(Vector3(3.0, 0.0, 0.0))
	_enemy(Vector3(4.0, 0.0, 0.0))
	_abilities.tick()
	assert_eq(_act.casts.size(), 1, "one throw")
	assert_eq(_act.casts[0]["caster"], caster)
	assert_eq(_act.casts[0]["id"], STRIKE)
	assert_almost_eq((_act.casts[0]["at"] as Vector3).x, 3.5, 0.001, "between the two")


func test_a_lone_enemy_is_a_rifles_job_not_a_charges() -> void:
	_caster([STRIKE])
	_enemy(Vector3(3.0, 0.0, 0.0))
	_abilities.tick()
	assert_eq(_act.casts, [])


func test_enemies_out_of_reach_are_not_struck() -> void:
	_caster([STRIKE])
	_enemy(Vector3(STRIKE_REACH + 1.0, 0.0, 0.0))
	_enemy(Vector3(STRIKE_REACH + 2.0, 0.0, 0.0))
	_abilities.tick()
	assert_eq(_act.casts, [])


func test_a_clump_with_one_of_ours_under_it_is_not_struck() -> void:
	_caster([STRIKE])
	_enemy(Vector3(3.0, 0.0, 0.0))
	_enemy(Vector3(4.0, 0.0, 0.0))
	_caster([], Vector3(3.5, 0.0, 1.0))  # a friend standing in the blast
	_abilities.tick()
	assert_eq(_act.casts, [], "the blast does not take sides")


func test_a_spread_out_pair_is_no_clump() -> void:
	_caster([STRIKE])
	_enemy(Vector3(2.0, 0.0, 0.0))
	_enemy(Vector3(-2.0, 0.0, 0.0))  # four apart: no blast of two covers both
	_abilities.tick()
	assert_eq(_act.casts, [])


func test_a_passive_ability_is_never_cast() -> void:
	_caster([PASSIVE])
	_enemy(Vector3(3.0, 0.0, 0.0))
	_enemy(Vector3(4.0, 0.0, 0.0))
	_abilities.tick()
	assert_eq(_act.casts, [])


func test_a_unit_on_an_errand_keeps_to_its_errand() -> void:
	var caster: Actor = _caster([STRIKE])
	_abilities.claims.claim(caster, &"economy", BotClaims.Priority.ERRAND)
	_enemy(Vector3(3.0, 0.0, 0.0))
	_enemy(Vector3(4.0, 0.0, 0.0))
	_abilities.tick()
	assert_eq(_act.casts, [])


func test_a_unit_mid_fight_still_throws() -> void:
	var caster: Actor = _caster([STRIKE])
	_abilities.claims.claim(caster, BotTargeting.CLAIM_OWNER, BotClaims.Priority.COMBAT)
	_enemy(Vector3(3.0, 0.0, 0.0))
	_enemy(Vector3(4.0, 0.0, 0.0))
	_abilities.tick()
	assert_eq(_act.casts.size(), 1, "the fight is where the clump is")


# ─── THE SIEGE LOOP ──────────────────────────────────────────────────────────


func test_a_loaded_gun_sends_a_spotter_to_the_believed_structure() -> void:
	_loaded_gun()
	var spotter: Actor = _caster([SPOT])
	_bot.believed_at = Vector3(80.0, 0.0, 0.0)
	_abilities.tick()
	assert_eq(_act.spots.size(), 1)
	assert_eq(_act.spots[0]["spotter"], spotter)
	assert_eq(_act.spots[0]["at"], Vector3(80.0, 0.0, 0.0))
	assert_true(_abilities.claims.owns(spotter, BotAbilities.CLAIM_OWNER), "an errand")


func test_with_no_loaded_gun_nobody_spots() -> void:
	_caster([SPOT])
	_bot.believed_at = Vector3(80.0, 0.0, 0.0)
	_abilities.tick()
	assert_eq(_act.spots, [], "a solution nobody can fire on")


func test_one_gun_wants_one_spotter() -> void:
	_loaded_gun()
	_caster([SPOT])
	_caster([SPOT])
	_bot.believed_at = Vector3(80.0, 0.0, 0.0)
	_abilities.tick()
	assert_eq(_act.spots.size(), 1)
	_abilities.tick()
	assert_eq(_act.spots.size(), 1, "and not a second while the first holds")


func test_with_nothing_believed_the_spotter_stays() -> void:
	_loaded_gun()
	_caster([SPOT])
	_abilities.tick()
	assert_eq(_act.spots, [])


func test_a_spotter_whose_solution_ended_is_given_back() -> void:
	_loaded_gun()
	var spotter: Actor = _caster([SPOT])
	_bot.believed_at = Vector3(80.0, 0.0, 0.0)
	_abilities.tick()
	spotter.update_commands(null)  # the gun fired, or it was re-ordered
	_abilities._release_finished_spotters()
	assert_false(_abilities.claims.is_claimed(spotter))
