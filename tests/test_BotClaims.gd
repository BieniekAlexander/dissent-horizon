extends GutTest

## BotClaims — which manager owns which unit. The managers run on independent periods, so this
## registry is the only thing standing between a scout and the army's rally, or a builder and a
## capture errand. These tests pin its rules against bare units.

const SCOUT: StringName = &"scout"
const ECONOMY: StringName = &"economy"
const OPPORTUNIST: StringName = &"opportunist"
const TARGETING: StringName = &"targeting"

var _claims: BotClaims


func before_each() -> void:
	_claims = BotClaims.new()


func _unit() -> Commandable:
	return autofree(Commandable.new()) as Commandable


func test_an_unclaimed_unit_is_the_armys() -> void:
	var unit := _unit()
	assert_false(_claims.is_claimed(unit))
	assert_eq(_claims.owner_of(unit), &"")


func test_a_claim_is_held_by_its_owner() -> void:
	var unit := _unit()
	assert_true(_claims.claim(unit, SCOUT, BotClaims.Priority.SCOUT))
	assert_true(_claims.owns(unit, SCOUT))
	assert_true(_claims.is_claimed(unit))
	assert_eq(_claims.units_of(SCOUT), [unit])


func test_a_stronger_claim_takes_the_unit() -> void:
	var unit := _unit()
	_claims.claim(unit, SCOUT, BotClaims.Priority.SCOUT)
	assert_true(
		_claims.claim(unit, TARGETING, BotClaims.Priority.COMBAT), "combat outranks scouting"
	)
	assert_false(_claims.owns(unit, SCOUT), "and the scout finds it gone")


func test_an_equal_claim_does_not_take_the_unit() -> void:
	var unit := _unit()
	_claims.claim(unit, ECONOMY, BotClaims.Priority.ERRAND)
	assert_false(
		_claims.claim(unit, OPPORTUNIST, BotClaims.Priority.ERRAND),
		"two errands never steal a unit back and forth"
	)
	assert_true(_claims.owns(unit, ECONOMY))


func test_a_weaker_claim_does_not_take_the_unit() -> void:
	var unit := _unit()
	_claims.claim(unit, TARGETING, BotClaims.Priority.COMBAT)
	assert_false(_claims.can_claim(unit, SCOUT, BotClaims.Priority.SCOUT))


func test_re_claiming_your_own_unit_succeeds_at_any_priority() -> void:
	var unit := _unit()
	_claims.claim(unit, ECONOMY, BotClaims.Priority.ERRAND)
	assert_true(_claims.claim(unit, ECONOMY, BotClaims.Priority.ERRAND))


func test_only_the_owner_can_release() -> void:
	var unit := _unit()
	_claims.claim(unit, ECONOMY, BotClaims.Priority.ERRAND)
	_claims.release(unit, SCOUT)
	assert_true(_claims.owns(unit, ECONOMY), "a release by someone else is a no-op")
	_claims.release(unit, ECONOMY)
	assert_false(_claims.is_claimed(unit))


func test_a_freed_unit_drops_its_claim() -> void:
	var unit := Commandable.new()
	_claims.claim(unit, SCOUT, BotClaims.Priority.SCOUT)
	unit.free()
	assert_false(_claims.owns(unit, SCOUT), "a freed unit is owned by nobody")
	assert_eq(_claims.units_of(SCOUT), [])
