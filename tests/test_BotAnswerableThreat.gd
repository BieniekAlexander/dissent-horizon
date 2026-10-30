extends GutTest

## Bot.can_answer — whether anything the bot fields can damage a given enemy. The one question
## every threat sense that moves the ARMY or spends the BANK now asks (bot.gd §Answerable
## threats): a raider nothing can hit is a reason to buy the counter, never to march units at
## it, call builders home or release the savings. The senses themselves are pinned in
## test_BotThreatSenses, test_BotStaging, test_BotBuilderAbort and test_BotDefenceDemand through
## stubs of this predicate; this file is the predicate against real weapons and real altitude.

var _scenario: Scenario
var _bot: Bot
var _foe: Commander


func before_each() -> void:
	_scenario = autofree(Scenario.new()) as Scenario
	_bot = _commander(Bot.new(), 1) as Bot
	_foe = _commander(Commander.new(), 2)
	_scenario.commanders = [_bot, _foe]


func _commander(a_commander: Commander, a_id: int) -> Commander:
	a_commander.id = a_id
	a_commander.initialize(null, _scenario)
	add_child_autofree(a_commander)
	return a_commander


## A piece of the bot's own: a unit, or a structure when asked.
func _own(a_options: Dictionary, a_structure: bool = false) -> Actor:
	var piece: Actor = (
		FakePieces.structure(a_options) if a_structure else FakePieces.unit(a_options)
	)
	_bot.add_child(piece)
	autofree(piece)
	piece.ownership.commander = _bot
	return piece


## Enemy infantry on the ground.
func _grunt() -> Actor:
	var piece: Actor = FakePieces.unit({"speed": 2.0})
	_foe.add_child(piece)
	autofree(piece)
	piece.ownership.commander = _foe
	piece.global_position = Vector3(10.0, 0.0, 0.0)
	return piece


## An enemy aircraft at cruise altitude. The altitude is set by hand because is_air_target
## reads a height, and nothing lifts a piece off the deck in a test with no physics running
## (tests/test_AirTargetAltitude.gd).
func _clipper() -> Actor:
	var piece: Actor = FakePieces.unit(FakePieces.AIRCRAFT)
	_foe.add_child(piece)
	autofree(piece)
	piece.ownership.commander = _foe
	piece.global_position = Vector3(10.0, 0.0, 0.0)
	piece.aerial._current_height_offset = Aerial.AERIAL_HEIGHT
	piece.refresh_targetable_altitude()
	return piece


func test_the_fixture_is_honest() -> void:
	var clipper: Actor = _clipper()
	assert_ne(clipper.targetable_layers() & CollisionLayers.Mask.TARGETABLE_AIR, 0)
	assert_eq(clipper.targetable_layers() & CollisionLayers.Mask.TARGETABLE_GROUND, 0)
	assert_ne(_grunt().targetable_layers() & CollisionLayers.Mask.TARGETABLE_GROUND, 0)


func test_a_bot_fielding_nothing_answers_nothing() -> void:
	assert_false(_bot.can_answer(_grunt()))


func test_a_ground_gun_answers_infantry_but_not_an_aircraft() -> void:
	_own(FakePieces.SOLDIER)
	assert_true(_bot.can_answer(_grunt()))
	assert_false(_bot.can_answer(_clipper()), "eighty of these could not touch five Clippers")


func test_an_anti_air_gun_answers_the_aircraft() -> void:
	_own({"speed": 2.0, "weapon": {"air": 6.0}})
	assert_true(_bot.can_answer(_clipper()))


func test_an_armed_structure_answers_too_once_it_is_built() -> void:
	# The SAM is the answer the demand read buys; once it STANDS, the Clipper is answerable. A
	# SAM still going up is not an answer yet, or the army turned to DEFEND the moment the build
	# was ordered, under the very guns it could not shoot back at.
	# is_built is read from build_progress: a structure counts as built at 1.0.
	var sam: Actor = _own({"weapon": {"air": 6.0}}, true)
	sam.build_progress = Actor.INITIAL_BUILD_PROGRESS
	assert_false(sam.is_built, "guards the fixture")
	assert_false(_bot.can_answer(_clipper()), "a foundation shoots nothing")
	sam.build_progress = 1.0
	assert_true(_bot.can_answer(_clipper()))


func test_an_unarmed_builder_answers_nothing() -> void:
	_own({"speed": 2.0})
	assert_false(_bot.can_answer(_grunt()))


func test_a_crusher_answers_what_it_can_run_over_and_nothing_in_the_air() -> void:
	_own({"speed": 2.0, "crush": Movement.CrushClass.LARGE})
	assert_true(_bot.can_answer(_grunt()), "crush is lethality")
	assert_false(_bot.can_answer(_clipper()))


func test_one_answering_piece_anywhere_is_enough() -> void:
	# Answerable is about CAPABILITY, not reach: the predicate asks whether the bot has an
	# answer at all, and the senses that use it decide where it stands.
	_own(FakePieces.SOLDIER)
	var far: Actor = _own({"speed": 2.0, "weapon": {"air": 6.0}})
	far.global_position = Vector3(500.0, 0.0, 500.0)
	assert_true(_bot.can_answer(_clipper()))
