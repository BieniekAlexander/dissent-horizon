extends GutTest

## THE BOT DOES NOT SEND TWO BUILDERS AT ONE STRUCTURE.
##
## Co-building is a real mechanic and a player may want it, but an extra worker no longer
## shortens the build, so for the bot a second builder on the same site is pure waste — and
## it is what `build_concurrency` produced the moment it rose above 1 (2026-09-12).
##
## The mechanism: `BotEconomy.tick()` picks ONE builder and walks a priority ladder. A job
## that has been ORDERED but has not PLACED its structure yet is invisible to every "do I own
## one of these" check in that ladder — the structure does not exist to be counted — so the
## next think pass re-runs the ladder, reaches the same rung, picks the same spot, and lands a
## second builder on the first one's site. Observed directly: both Servants on `site(0,64)`,
## then both on `Assemble@cl_infrastructure#669`.
##
## Two guards, and this pins both:
##   * `_types_under_way()` — an ordered building counts as owned by the "exactly one" rungs.
##   * `_is_claimed_spot()` — a site another job is already aimed at is not an available site.
##     This is the job `build_concurrency = 1` used to do by never running a second build; the
##     old comment on that gate said so ("racing two builds onto the same cells").

## SYNTHETIC ids, set onto real instances. The test is about the bot's bookkeeping, not about
## which pieces a faction ships, so it must not go red when content is renamed
## (CLAUDE.md §A unit test does not assert facts about authored content).
const DOMINION: StringName = &"test_compound"
const OTHER: StringName = &"test_barracks"

## load() inside the test, never a file-scope preload of an entity scene — that runs at PARSE
## time and can fire Tool's static registry initialiser before the registry exists (CLAUDE.md).
const BUILDER_SCENE: Dictionary = FakePieces.BUILDER
const STRUCTURE_SCENE: Dictionary = FakePieces.BUILDING


class FakeBot:
	extends Bot
	var units: Array = []
	var owned: Array = []

	func can_afford(_a_type: StringName) -> bool:
		return true

	func get_units() -> Array:
		return units

	func get_structures_of_type(_a_type: StringName) -> Array:
		return owned

	func buildable_dominion_structure_types() -> Array:
		return [DOMINION]


func _economy(a_bot: FakeBot) -> BotEconomy:
	return autofree(BotEconomy.new(a_bot, autofree(BotActuator.new(null))))


## A real instance, because a bare `Commandable.new()` has none of the component nodes its
## @onready lookups expect and pushes errors the moment anything touches it.
func _instance(a_options: Dictionary) -> Commandable:
	var unit := FakePieces.make(a_options) as Commandable
	add_child_autofree(unit)
	return unit


## A live unit holding `a_command`, which is what makes it read as constructing.
func _builder_running(a_command: MoveCommand) -> Commandable:
	var unit: Commandable = _instance(BUILDER_SCENE)
	unit.update_commands([a_command] as Array[MoveCommand])
	return unit


func _build_at(a_type: StringName, a_where: Vector3) -> MoveCommand:
	var tool := Tool.new("command_tool_%s" % a_type, a_type, null, str(a_type), Vector2i.ZERO, 0, 0)
	return Build.new(CommandMessage.new(null, null, tool, a_where))


func _assemble_on(a_structure: Commandable) -> MoveCommand:
	return Assemble.new(CommandMessage.new(null, a_structure, null, a_structure.global_position))


#region What an in-flight job claims
func test_a_build_order_reports_the_type_it_is_raising() -> void:
	var bot: FakeBot = autofree(FakeBot.new())
	bot.units = [_builder_running(_build_at(DOMINION, Vector3.ZERO))]
	assert_eq(
		_economy(bot)._types_under_way(),
		[DOMINION] as Array[StringName],
		"a type is claimed from the moment it is ORDERED, not when it is placed"
	)


func test_an_assemble_reports_the_structure_it_is_finishing() -> void:
	# The second half of a build's life: once the structure exists the tool is gone and the
	# claim has to come off the target instead.
	var structure: Commandable = _instance(STRUCTURE_SCENE)
	structure.id = DOMINION
	var bot: FakeBot = autofree(FakeBot.new())
	bot.units = [_builder_running(_assemble_on(structure))]
	assert_eq(_economy(bot)._types_under_way(), [DOMINION] as Array[StringName])


func test_an_idle_builder_claims_nothing() -> void:
	var bot: FakeBot = autofree(FakeBot.new())
	bot.units = [_instance(BUILDER_SCENE)]
	assert_eq(_economy(bot)._types_under_way(), [] as Array[StringName])
	assert_false(_economy(bot)._is_claimed_spot(Vector3.ZERO))


#endregion


#region The site is not available twice
func test_a_site_an_in_flight_job_is_aimed_at_is_claimed() -> void:
	var bot: FakeBot = autofree(FakeBot.new())
	bot.units = [_builder_running(_build_at(DOMINION, Vector3(10.0, 0.0, 10.0)))]
	assert_true(_economy(bot)._is_claimed_spot(Vector3(10.0, 0.0, 10.0)), "the same spot")
	assert_true(
		_economy(bot)._is_claimed_spot(Vector3(11.0, 0.0, 10.0)),
		"and one close enough to be racing for the same cells"
	)


func test_a_site_well_clear_of_every_job_is_free() -> void:
	var bot: FakeBot = autofree(FakeBot.new())
	bot.units = [_builder_running(_build_at(DOMINION, Vector3(10.0, 0.0, 10.0)))]
	assert_false(
		_economy(bot)._is_claimed_spot(Vector3(40.0, 0.0, 40.0)),
		"the rule must not make the map unbuildable"
	)


#endregion


#region The ladder reads an ordered building as handled
func test_the_dominion_rung_offers_nothing_while_one_is_already_ordered() -> void:
	# The exact failure: the Compound is not owned yet (it has not been placed), so without
	# the in-flight check this rung offers it again and a second builder joins the first.
	var bot: FakeBot = autofree(FakeBot.new())
	bot.units = [_builder_running(_build_at(DOMINION, Vector3.ZERO))]
	assert_null(_economy(bot)._dominion_structure_to_build(), "an ordered Compound counts as owned")


func test_the_dominion_rung_still_offers_one_when_nothing_is_under_way() -> void:
	# The control — the guard must not switch the rung off altogether.
	var bot: FakeBot = autofree(FakeBot.new())
	assert_eq(
		_economy(bot)._dominion_structure_to_build(),
		DOMINION,
		"with no job in flight the bot still builds its dominion structure"
	)


func test_a_job_for_a_different_type_does_not_block_the_dominion_rung() -> void:
	var bot: FakeBot = autofree(FakeBot.new())
	bot.units = [_builder_running(_build_at(OTHER, Vector3.ZERO))]
	assert_eq(
		_economy(bot)._dominion_structure_to_build(),
		DOMINION,
		"only the SAME type counts as already handled"
	)
#endregion
