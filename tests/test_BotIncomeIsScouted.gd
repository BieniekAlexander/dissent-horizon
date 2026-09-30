extends GutTest

## The bot's extraction-site search is fog-limited: a site it has never had in vision is one it
## does not know exists, and whether one is taken is a BELIEF — read live only for its own
## extractor or one in its vision (bot-architecture.md §Income is found by scouting). The pond
## half of the same rule is pinned in test_WaterPlacement.gd, beside the pond fixture it needs.

const SITE_SCENE: Dictionary = {"structure": true, "extraction_site": true}
const WORKER_SCENE: Dictionary = FakePieces.BUILDER
const BOT_ID: int = 2
const ENEMY_ID: int = 1
const NEAR: Vector3 = Vector3(5.0, 0.0, 0.0)
const FAR: Vector3 = Vector3(40.0, 0.0, 0.0)


## Enough of a Bot for the site search: a base at the origin, a set of explored points, a set
## of points in vision now, and a blackboard the tests write beliefs into.
class StubBot extends Bot:
	var explored: Array[Vector3] = []
	var in_vision: Array[Vector3] = []

	func base_centroid() -> Vector3:
		return Vector3.ZERO

	func has_explored(a_world_pos: Vector3) -> bool:
		return explored.any(func(p: Vector3) -> bool: return p.is_equal_approx(a_world_pos))

	func has_vision_at(a_world_pos: Vector3) -> bool:
		return in_vision.any(func(p: Vector3) -> bool: return p.is_equal_approx(a_world_pos))


func _bot() -> StubBot:
	var bot: StubBot = StubBot.new()
	bot.id = BOT_ID
	add_child_autofree(bot)
	bot.blackboard = CommanderBlackboard.new(bot)
	return bot


## A live piece owned by commander `a_owner_id`, standing at `a_position`, to act as a claimant.
func _extractor_at(a_position: Vector3, a_owner_id: int) -> Commandable:
	var owner: Commander = Commander.new()
	owner.id = a_owner_id
	add_child_autofree(owner)
	var piece: Commandable = FakePieces.make(WORKER_SCENE) as Commandable
	add_child_autofree(piece)
	piece.ownership.commander = owner
	piece.global_position = a_position
	return piece


## Tell `a_bot` it remembers an enemy structure at `a_position`.
func _remember_structure_at(a_bot: StubBot, a_position: Vector3) -> void:
	var entry := CommanderBlackboard.Entry.new()
	entry.instance_id = 1
	entry.is_structure = true
	entry.last_known_location = a_position
	a_bot.blackboard._entries[entry.instance_id] = entry


## A real extraction site piece, loaded inside the test (a file-scope preload of an entity
## scene can poison the Tool registry — CLAUDE.md).
func _site_at(a_position: Vector3) -> Entity:
	var site: Entity = FakePieces.make(SITE_SCENE) as Entity
	add_child_autofree(site)
	site.global_position = a_position
	return site


func _economy(a_bot: Bot) -> BotEconomy:
	return autofree(BotEconomy.new(a_bot, autofree(BotActuator.new(null))))


func test_an_unexplored_site_is_never_offered() -> void:
	_site_at(NEAR)
	assert_null(_economy(_bot())._nearest_unclaimed_site(),
		"the only site has never been seen, so the bot knows of none")


func test_the_nearest_explored_site_wins_over_a_nearer_unexplored_one() -> void:
	var bot: StubBot = _bot()
	_site_at(NEAR)
	var far: Entity = _site_at(FAR)
	bot.explored = [FAR]
	assert_eq(_economy(bot)._nearest_unclaimed_site(), far,
		"distance only ranks the sites the bot has actually found")


func test_the_income_spot_is_null_until_something_is_found() -> void:
	# No map, so no ponds: the site search is the whole answer here.
	_site_at(NEAR)
	assert_null(_economy(_bot())._income_build_spot(),
		"with nothing explored the income rung has nowhere to build")


#region Whether it is taken is a belief
func test_a_site_taken_out_of_sight_still_reads_open() -> void:
	var bot: StubBot = _bot()
	var site: Entity = _site_at(NEAR)
	bot.explored = [NEAR]
	ExtractionSite.of(site).extractor = _extractor_at(NEAR, ENEMY_ID)
	assert_eq(_economy(bot)._nearest_unclaimed_site(), site,
		"the bot has not seen the enemy extractor, so it believes the site is free")


func test_a_site_taken_in_sight_is_skipped() -> void:
	var bot: StubBot = _bot()
	var taken: Entity = _site_at(NEAR)
	var open: Entity = _site_at(FAR)
	bot.explored = [NEAR, FAR]
	bot.in_vision = [NEAR]
	ExtractionSite.of(taken).extractor = _extractor_at(NEAR, ENEMY_ID)
	assert_eq(_economy(bot)._nearest_unclaimed_site(), open,
		"a claim the bot can see is a claim it knows about")


func test_its_own_claim_is_known_without_looking() -> void:
	var bot: StubBot = _bot()
	var site: Entity = _site_at(NEAR)
	bot.explored = [NEAR]
	ExtractionSite.of(site).extractor = _extractor_at(NEAR, BOT_ID)
	assert_null(_economy(bot)._nearest_unclaimed_site(),
		"the bot always knows where its own extractors are")


func test_a_remembered_claim_holds_after_the_extractor_is_gone() -> void:
	var bot: StubBot = _bot()
	_site_at(NEAR)
	bot.explored = [NEAR]
	_remember_structure_at(bot, NEAR)
	assert_null(_economy(bot)._nearest_unclaimed_site(),
		"it last saw an enemy structure on the site, and has not looked since")


func test_a_remembered_structure_elsewhere_claims_nothing() -> void:
	var bot: StubBot = _bot()
	var site: Entity = _site_at(NEAR)
	bot.explored = [NEAR]
	_remember_structure_at(bot, FAR)
	assert_eq(_economy(bot)._nearest_unclaimed_site(), site,
		"a belief claims only the site it stands on")
#endregion
