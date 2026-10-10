extends GutTest
## WHICH SITE THE BOT WORKS NEXT is the most valuable, not the nearest (bot-architecture.md
## §The bot works lithium ponds; lattice-and-topology.md §Safety, sites and placement, item 2):
## every site and pond in one comparison by rate × expected lifetime, less what the walk and
## the build defer and the extractor's price; a site the builder could not finish is refused.

const EXTRACTOR: StringName = &"fake_extractor"
const RATE: float = 5.0
const PRICE: float = 300.0
const EPS: float = 1e-4


## A bot whose rates, lifetimes and kill clocks are what a test says, per spot.
class FakeBot:
	extends Bot
	var lifetimes: Dictionary = {}
	var kills: Dictionary = {}

	func home_centroid() -> Vector3:
		return Vector3.ZERO

	func income_rate_of_type(_a_type: StringName) -> float:
		return RATE

	func lifetime_of_type_at(_a_type: StringName, a_xz: Vector2) -> float:
		return float(lifetimes.get(a_xz, BotFields.HELD_LIFETIME_SECONDS))

	func kill_seconds_of_at(_a_piece: Actor, a_xz: Vector2) -> float:
		return float(kills.get(a_xz, INF))


## An economy whose candidates and build window are what a test says.
class StubEconomy:
	extends BotEconomy
	var candidates: Array = []
	var window: float = 20.0

	func _extractor_type() -> StringName:
		return EXTRACTOR

	func _energy_cost(_a_type) -> int:
		return int(PRICE)

	func _site_candidates() -> Array:
		return candidates

	func _build_window_seconds(_a_builder: Actor, _a_spot: Vector3, _a_type: StringName) -> float:
		return window


func _site(a_x: float) -> Dictionary:
	return {"spot": Vector3(a_x, 0.0, 0.0), "rate_multiplier": 1.0, "reservoir": INF}


func _pond(a_x: float, a_energy: float) -> Dictionary:
	return {
		"spot": Vector3(a_x, 0.0, 0.0),
		"rate_multiplier": float(WaterBody.POND_RATE_MULTIPLIER),
		"reservoir": a_energy,
	}


func _economy(a_bot: FakeBot, a_candidates: Array) -> StubEconomy:
	var economy := StubEconomy.new(a_bot, null)
	economy.candidates = a_candidates
	return economy


func _bot() -> FakeBot:
	return autofree(FakeBot.new())


# ─── THE VALUE OF A SITE ────────────────────────────────────────────────────


func test_a_site_is_worth_its_rate_for_the_time_it_earns_less_its_price() -> void:
	assert_almost_eq(BotEconomy.site_value(5.0, 300.0, INF, 20.0, 300.0), 5.0 * 280.0 - 300.0, EPS)
	assert_almost_eq(
		BotEconomy.site_value(15.0, 300.0, 4500.0, 20.0, 300.0),
		4200.0 - 300.0,
		EPS,
		"a pond at thrice the rate, its reservoir not yet the cap"
	)
	assert_almost_eq(
		BotEconomy.site_value(15.0, 300.0, 1500.0, 20.0, 300.0),
		1500.0 - 300.0,
		EPS,
		"a pond that runs dry inside the horizon earns only what is in it"
	)
	assert_almost_eq(
		BotEconomy.site_value(5.0, 30.0, INF, 20.0, 300.0),
		50.0 - 300.0,
		EPS,
		"an exposed site earns for the ten seconds it has after the build"
	)
	assert_almost_eq(
		BotEconomy.site_value(5.0, 10.0, INF, 20.0, 300.0),
		-300.0,
		EPS,
		"one that falls before the build is done earns nothing"
	)


# ─── WHICH SITE IS WORKED ───────────────────────────────────────────────────


func test_a_richer_pond_beats_a_nearer_site_when_both_are_safe() -> void:
	var economy: StubEconomy = _economy(_bot(), [_site(5.0), _pond(40.0, 4500.0)])
	assert_eq(economy._income_build_spot(), Vector3(40.0, 0.0, 0.0))


func test_an_exposed_pond_loses_to_a_safe_site() -> void:
	var bot: FakeBot = _bot()
	bot.lifetimes[Vector2(40.0, 0.0)] = 40.0  # the pond falls 20 s after the build is done
	var economy: StubEconomy = _economy(bot, [_site(5.0), _pond(40.0, 4500.0)])
	assert_eq(
		economy._income_build_spot(),
		Vector3(5.0, 0.0, 0.0),
		"300 energy in twenty seconds against 1,400 over the horizon"
	)


func test_a_site_the_builder_would_die_at_is_refused_however_rich() -> void:
	var bot: FakeBot = _bot()
	bot.kills[Vector2(40.0, 0.0)] = 15.0  # inside the 20 s window
	var economy: StubEconomy = _economy(bot, [_site(5.0), _pond(40.0, 4500.0)])
	assert_eq(economy._income_build_spot(), Vector3(5.0, 0.0, 0.0))
	bot.kills[Vector2(40.0, 0.0)] = 20.0  # the builder finishes as they arrive
	assert_eq(
		economy._income_build_spot(), Vector3(40.0, 0.0, 0.0), "a window that closes in time holds"
	)
	bot.kills[Vector2(5.0, 0.0)] = 1.0
	bot.kills[Vector2(40.0, 0.0)] = 1.0
	assert_null(economy._income_build_spot(), "nowhere the builder could finish: nothing is taken")


func test_equal_sites_go_to_the_nearest_and_an_unreachable_one_is_skipped() -> void:
	var economy: StubEconomy = _economy(_bot(), [_site(40.0), _site(5.0), _site(-20.0)])
	assert_eq(
		economy._income_build_spot(),
		Vector3(5.0, 0.0, 0.0),
		"the rule this replaced, as the tie-break"
	)
	economy.window = INF
	assert_null(economy._income_build_spot(), "a spot the builder cannot reach is no candidate")


func test_a_site_not_worth_its_extractor_is_still_taken_when_nothing_better_is_known() -> void:
	var bot: FakeBot = _bot()
	bot.lifetimes[Vector2(5.0, 0.0)] = 40.0
	var economy: StubEconomy = _economy(bot, [_site(5.0)])
	assert_eq(economy._income_build_spot(), Vector3(5.0, 0.0, 0.0))
