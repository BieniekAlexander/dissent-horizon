extends GutTest
## The single-unit targetings: a sanction cast ON a unit of the bot's own. Both were aimed at
## ground and refused every time (NO_VALID_TARGET ×596 and ×790 in the first piece-usage
## audit); the unit is now chosen by what the event's own admission rule accepts.

const CHEAP: StringName = &"fake_cheap"
const DEAR: StringName = &"fake_dear"
const REJECTED: StringName = &"fake_rejected"


## A sanction whose event rejects REJECTED and accepts any other unit, without an event scene.
class StubSanction:
	extends Sanction

	func accepts_target(a_candidate: Variant, _a_commander: Commander) -> bool:
		return a_candidate is Actor and (a_candidate as Actor).id != REJECTED


var _bot: Bot
var _bo: BotSanction


func before_each() -> void:
	_bot = Bot.new()
	_bot.technology_mapping = {
		CHEAP: TechnologySpec.new(100, 0, 0, 30),
		DEAR: TechnologySpec.new(600, 0, 0, 30),
		REJECTED: TechnologySpec.new(900, 0, 0, 30),
	}
	add_child_autofree(_bot)
	_bo = BotSanction.new(_bot, null)
	_bo.defend_threat_radius = 10.0


## An owned unit of `a_id` at `a_at`, with `a_hp_fraction` of its hit points left.
func _own(a_id: StringName, a_at: Vector3, a_hp_fraction: float = 1.0) -> Actor:
	var unit: Actor = FakePieces.unit({"id": a_id, "hp": 100.0})
	_bot.add_child(unit)
	unit.ownership.commander = _bot
	unit.global_position = a_at
	unit.defense.hp = 100.0 * a_hp_fraction
	return unit


func _zone_at(a_anchor: Vector3) -> Dictionary:
	return {"mode": BotSanction.Mode.DEFEND, "enemies": [], "anchor": a_anchor}


func test_the_endangered_friend_is_the_dearest_hurt_unit_in_the_engagement() -> void:
	var sanction := StubSanction.new()
	sanction.targeting = Sanction.Targeting.ENDANGERED_FRIEND
	_own(CHEAP, Vector3(1, 0, 0), 0.2)
	var dear: Actor = _own(DEAR, Vector3(2, 0, 0), 0.4)
	_own(DEAR, Vector3(3, 0, 0), 0.9)  # dear, but healthy
	_own(DEAR, Vector3(50, 0, 0), 0.1)  # dear and dying, but not in this fight
	assert_eq(_bo._aim(sanction, _zone_at(Vector3.ZERO)), dear)


func test_no_hurt_friend_means_the_charge_is_held() -> void:
	var sanction := StubSanction.new()
	sanction.targeting = Sanction.Targeting.ENDANGERED_FRIEND
	_own(DEAR, Vector3(1, 0, 0), 0.9)
	assert_null(_bo._aim(sanction, _zone_at(Vector3.ZERO)))


func test_the_event_decides_who_may_be_targeted() -> void:
	var sanction := StubSanction.new()
	sanction.targeting = Sanction.Targeting.ENDANGERED_FRIEND
	_own(REJECTED, Vector3(1, 0, 0), 0.1)
	var cheap: Actor = _own(CHEAP, Vector3(2, 0, 0), 0.1)
	assert_eq(_bo._aim(sanction, _zone_at(Vector3.ZERO)), cheap, "dearer, but refused")


func test_the_valuable_friend_is_the_dearest_accepted_unit_fight_or_none() -> void:
	var sanction := StubSanction.new()
	sanction.targeting = Sanction.Targeting.VALUABLE_FRIEND
	_own(CHEAP, Vector3(1, 0, 0))
	var dear: Actor = _own(DEAR, Vector3(80, 0, 0))
	_own(REJECTED, Vector3(2, 0, 0))
	assert_eq(_bo._aim(sanction, {}), dear)
	assert_false(sanction.targeting_needs_engagement())


func test_a_reveal_is_aimed_at_unscouted_ground_nearest_the_enemy() -> void:
	var sanction := Sanction.new()
	sanction.targeting = Sanction.Targeting.REVEAL
	sanction.effect_radius = 24.0
	var scout := BotScout.new(_bot, null)
	_bo.scout = scout
	var expired: float = -(BotScout.SCOUT_EXPIRATION_TIMER + 1.0)
	scout._scout_grid[Vector2i(0, 0)] = expired
	scout._scout_grid_positions[Vector2i(0, 0)] = Vector3(40, 0, 0)
	scout._scout_grid[Vector2i(1, 0)] = expired
	scout._scout_grid_positions[Vector2i(1, 0)] = Vector3(10, 0, 0)
	scout._scout_grid[Vector2i(2, 0)] = 0.0  # seen just now
	scout._scout_grid_positions[Vector2i(2, 0)] = Vector3(5, 0, 0)
	# Nothing believed and no map: the bot aims from its own base, at the origin.
	assert_eq(_bo._aim(sanction, {}), Vector3(10, 0, 0), "nearest unscouted, not nearest")
	assert_false(sanction.targeting_needs_engagement())
	scout.mark_revealed(Vector3(10, 0, 0), 24.0)
	assert_eq(_bo._aim(sanction, {}), Vector3(40, 0, 0), "what a Scan showed is scouted now")
	assert_true(scout.observed_point_count() >= 2)
