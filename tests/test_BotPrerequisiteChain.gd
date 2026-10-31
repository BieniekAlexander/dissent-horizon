extends GutTest

## THE CHAIN A PURCHASE STILL NEEDS (Bot.prerequisite_chain; Alex, 2026-10-30: an unowned
## prerequisite is part of the price). Every structure a type requires, recursively, that the
## bot neither owns nor has on its way, in build order, with the summed cost and whether some
## owned builder could place every link — and the price it makes: chain_cost and
## chain_price_factor, which every purchase rung reads through Bot.purchase_values_per_energy.
## The tech tree is REAL (TechnologySpec); what is owned and what a builder may place are the
## fixture's tables.

const BARRACKS: StringName = &"test_barracks"
const FACTORY: StringName = &"test_factory"  # requires the barracks
const ACADEMY: StringName = &"test_academy"  # requires the factory
const CONSTABLE: StringName = &"test_constable"  # requires the academy
const SAM: StringName = &"test_sam"  # requires the factory
const RECRUIT: StringName = &"test_recruit"  # requires nothing


class FakeBot:
	extends Bot
	var owned: Array = []
	var incoming: Array = []
	var placeable: Array = [BARRACKS, FACTORY, ACADEMY, SAM]

	func get_structures_of_type(a_type: StringName) -> Array:
		return [null] if owned.has(a_type) else []

	func has_incoming_structure(a_id: StringName) -> bool:
		return incoming.has(a_id)

	func builder_may_place(a_type: StringName) -> bool:
		return placeable.has(a_type)


var _bot: FakeBot


func before_each() -> void:
	_bot = FakeBot.new()
	_bot.technology_mapping = {
		BARRACKS: TechnologySpec.new(300, 0, 0, 30),
		FACTORY: TechnologySpec.new(1200, 0, 0, 30, [BARRACKS]),
		ACADEMY: TechnologySpec.new(1000, 0, 0, 30, [FACTORY]),
		CONSTABLE: TechnologySpec.new(400, 0, 0, 30, [ACADEMY]),
		SAM: TechnologySpec.new(400, 0, 0, 30, [FACTORY]),
		RECRUIT: TechnologySpec.new(100, 0, 0, 30),
	}


func after_each() -> void:
	_bot.free()


func test_the_chain_is_every_unowned_prerequisite_in_build_order() -> void:
	var chain: Dictionary = _bot.prerequisite_chain(CONSTABLE)
	assert_eq(chain["structures"], [BARRACKS, FACTORY, ACADEMY] as Array[StringName])
	assert_eq(chain["cost"], 2500)
	assert_true(chain["placeable"])


func test_an_owned_structure_and_everything_beneath_it_cost_nothing_more() -> void:
	_bot.owned = [FACTORY]
	var chain: Dictionary = _bot.prerequisite_chain(CONSTABLE)
	assert_eq(chain["structures"], [ACADEMY] as Array[StringName], "the barracks is not asked")
	assert_eq(chain["cost"], 1000)


func test_a_structure_on_its_way_is_as_good_as_owned() -> void:
	_bot.incoming = [BARRACKS]
	assert_eq(_bot.prerequisite_chain(SAM)["structures"], [FACTORY] as Array[StringName])
	assert_eq(_bot.prerequisite_chain(SAM, [FACTORY])["structures"], [] as Array[StringName])


func test_a_type_the_bot_can_produce_today_has_no_chain() -> void:
	var chain: Dictionary = _bot.prerequisite_chain(RECRUIT)
	assert_eq(chain["structures"], [] as Array[StringName])
	assert_eq(chain["cost"], 0)
	assert_true(chain["placeable"])


func test_a_type_with_no_spec_has_no_chain() -> void:
	assert_eq(_bot.prerequisite_chain(&"test_unknown")["cost"], 0)


func test_a_link_no_builder_may_place_makes_the_chain_unplaceable() -> void:
	_bot.placeable = [BARRACKS, FACTORY]
	assert_false(_bot.prerequisite_chain(CONSTABLE)["placeable"], "the academy cannot be placed")
	assert_true(_bot.prerequisite_chain(SAM)["placeable"])


func test_a_cycle_in_the_tree_ends_the_chain_rather_than_looping() -> void:
	_bot.technology_mapping[BARRACKS] = TechnologySpec.new(300, 0, 0, 30, [ACADEMY])
	var chain: Dictionary = _bot.prerequisite_chain(CONSTABLE)
	assert_eq(chain["structures"].size(), 3, "each structure once")


func test_a_shared_prerequisite_is_counted_once() -> void:
	_bot.technology_mapping[CONSTABLE] = TechnologySpec.new(400, 0, 0, 30, [ACADEMY, SAM])
	var chain: Dictionary = _bot.prerequisite_chain(CONSTABLE)
	assert_eq(chain["structures"], [BARRACKS, FACTORY, ACADEMY, SAM] as Array[StringName])
	assert_eq(chain["cost"], 2900)


# ─── THE PRICE THE CHAIN MAKES ───────────────────────────────────────────────


func test_chain_cost_is_the_type_and_its_chain() -> void:
	assert_eq(_bot.chain_cost(SAM), 400 + 300 + 1200)
	_bot.owned = [BARRACKS, FACTORY]
	assert_eq(_bot.chain_cost(SAM), 400, "nothing missing: its own price")


func test_the_price_factor_turns_a_value_per_own_energy_into_one_per_chain_energy() -> void:
	assert_almost_eq(_bot.chain_price_factor(SAM), 400.0 / 1900.0, 1e-9)
	assert_eq(_bot.chain_price_factor(RECRUIT), 1.0)


func test_a_type_priced_at_nothing_behind_a_chain_is_priced_as_if_it_cost_one() -> void:
	_bot.technology_mapping[SAM] = TechnologySpec.new(0, 0, 0, 30, [FACTORY])
	assert_almost_eq(_bot.chain_price_factor(SAM), 1.0 / 1500.0, 1e-9)
