extends GutTest

## WHO DRAWS THE SHROUD — the election in `Fog.terrain_fog_driver_id`.
##
## Fog is sampled per-fragment by the terrain shader, so the shroud only appears when some
## node pushes `fog_texture` / `fog_enabled` into the terrain MATERIAL. Exactly one node may:
## the material is shared, and two writers would fight over `fog_enabled` every frame.
##
## THE BUG THIS PINS. That role used to be spelled "the fog whose viewer id is
## `RTSController.PLAYER_COMMANDER_ID`". In an ALL-BOT scenario there is no local human, so
## `Scenario._build_commanders` leaves `PLAYER_COMMANDER_ID` at 0 while every bot Fog resolves
## to 1, 2, … — the test matched nobody, `fog_enabled` was never set, and the fog mesh simply
## never drew. Nothing else was broken, which is exactly why it presented as "none of the
## settings show the fog of war mesh, though it does correctly hide unseen buildings":
## entity visibility runs off `Fog.active_commander_id` and kept working the whole time.
##
## The three tests below are the three session shapes. `_old_rule` is the pre-fix predicate
## written out verbatim, so the second test can show it failing rather than assert it did.
##
## PATHS, not preloads — a file-scope preload of an entity scene poisons the Tool registry
## for the whole run (CLAUDE.md §A file-scope `preload`…). Nothing is preloaded here at all.

## A spectator session: Scenario leaves this at 0 when no player slot is a human.
const SPECTATOR: int = 0

var _saved_player_id: int


func before_each() -> void:
	_saved_player_id = RTSController.PLAYER_COMMANDER_ID
	Fog._fogs_by_commander.clear()


func after_each() -> void:
	# PLAYER_COMMANDER_ID is a static, so a test that left it moved would corrupt every test
	# after it — the same care test_Elimination takes.
	RTSController.PLAYER_COMMANDER_ID = _saved_player_id
	Fog._fogs_by_commander.clear()


## A Fog in the tree with no Map, so it stays inert — enough to register itself, which is all
## the election reads.
func _fog(a_watching_id: int) -> Fog:
	var fog := Fog.new()
	fog.watching_commander_id = a_watching_id
	add_child_autofree(fog)
	return fog


## The predicate as it read before the fix, so the regression is DEMONSTRATED here rather
## than described in a comment.
func _old_rule(a_fog: Fog) -> bool:
	return a_fog.viewer_commander_id() == RTSController.PLAYER_COMMANDER_ID


func test_a_human_session_still_elects_the_players_own_fog() -> void:
	RTSController.PLAYER_COMMANDER_ID = 1
	var human: Fog = _fog(-1)  # -1 is the authoring default in player.tscn: "the local player"
	_fog(2)
	assert_eq(Fog.terrain_fog_driver_id(), 1, "the human is commander 1 and wins the election")
	assert_true(_old_rule(human), "and the old rule agreed — a human session never broke")


func test_an_all_bot_session_elects_a_driver_where_the_old_rule_elected_nobody() -> void:
	RTSController.PLAYER_COMMANDER_ID = SPECTATOR
	var bot_one: Fog = _fog(1)
	var bot_two: Fog = _fog(2)

	# The regression, stated as the failure it was: under the old predicate NEITHER fog drove,
	# so nothing ever wrote fog_enabled and the shroud did not render.
	assert_false(_old_rule(bot_one), "pre-fix: bot 1 did not drive")
	assert_false(_old_rule(bot_two), "pre-fix: bot 2 did not drive either — nobody did")

	assert_eq(Fog.terrain_fog_driver_id(), 1, "the lowest-numbered bot now drives")


func test_exactly_one_registered_fog_drives() -> void:
	RTSController.PLAYER_COMMANDER_ID = SPECTATOR
	var fogs: Array[Fog] = [_fog(3), _fog(1), _fog(2)]
	var driver_id: int = Fog.terrain_fog_driver_id()
	var drivers: int = 0
	for fog: Fog in fogs:
		if fog.viewer_commander_id() == driver_id:
			drivers += 1
	assert_eq(drivers, 1, "one writer to the shared terrain material, never two")


func test_registration_order_does_not_decide_it() -> void:
	# Registration order is _ready order, which is scene order — not something the renderer
	# should inherit. Electing by id makes the answer the same either way.
	RTSController.PLAYER_COMMANDER_ID = SPECTATOR
	_fog(5)
	_fog(2)
	assert_eq(Fog.terrain_fog_driver_id(), 2)
	Fog._fogs_by_commander.clear()
	_fog(2)
	_fog(5)
	assert_eq(Fog.terrain_fog_driver_id(), 2)


func test_a_freed_fog_does_not_win_the_election() -> void:
	# Entries outlive the nodes that made them — a freed Fog never deregisters — so a stale
	# low id would otherwise win and hand the role to nobody at all.
	RTSController.PLAYER_COMMANDER_ID = SPECTATOR
	var dead := Fog.new()
	dead.watching_commander_id = 1
	add_child(dead)
	remove_child(dead)
	dead.free()
	_fog(4)
	assert_eq(Fog.terrain_fog_driver_id(), 4)


func test_with_no_fog_at_all_nobody_drives() -> void:
	RTSController.PLAYER_COMMANDER_ID = SPECTATOR
	# -1 is not a legal viewer id (viewer_commander_id resolves the -1 default away), so no
	# live fog can match it and the caller simply does not drive.
	assert_eq(Fog.terrain_fog_driver_id(), -1)
