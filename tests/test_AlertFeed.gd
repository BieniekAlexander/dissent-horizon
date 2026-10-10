extends GutTest

## THE PLAYER'S ALERT TOASTS AND THE JUMP KEY.
##
## Run with:
## godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_AlertFeed.gd -gexit
##
## A bare AlertFeed fed alerts by hand. Layout is not checked here (GUT cannot see it — see
## CLAUDE.md §Seeing the HUD without a screen). Why: gdd/systems/ux/ui/alerts.md §Presentation.

const ME: int = 1

var _feed: AlertFeed
var _jumps: Array[Vector2] = []

const SETTINGS: String = "user://test_alert_feed_settings.cfg"


func before_each() -> void:
	GameSettings.path = SETTINGS
	GameSettings.reset()
	_feed = AlertFeed.new()
	_feed.viewer = func() -> int: return ME
	add_child_autofree(_feed)
	_jumps.clear()
	_feed.jump_requested.connect(func(xz: Vector2) -> void: _jumps.append(xz))


func after_each() -> void:
	DirAccess.remove_absolute(SETTINGS)
	GameSettings.path = GameSettings.PATH
	GameSettings.reset()


func _located(a_x: float, a_viewer: int = ME) -> Alert:
	return Alert.make(AlertCatalog.Type.UNITS_ATTACKED, a_viewer, 0).located_at(Vector3(a_x, 0, 0))


func _toasts() -> int:
	return _feed.get_children().filter(func(c: Node) -> bool: return c is PanelContainer).size()


func test_only_the_viewers_alerts_are_shown() -> void:
	_feed.present(_located(0.0, 2))
	assert_eq(_toasts(), 0)
	_feed.present(_located(0.0))
	assert_eq(_toasts(), 1)


func test_the_jump_key_goes_to_the_newest_then_cycles_back() -> void:
	_feed.present(_located(100.0))
	_feed.present(_located(200.0))
	_feed.present(_located(300.0))
	for i: int in 4:
		_feed.jump_to_recent()
	assert_eq(_jumps, [Vector2(300, 0), Vector2(200, 0), Vector2(100, 0), Vector2(300, 0)])


func test_a_new_alert_resets_the_cycle() -> void:
	_feed.present(_located(100.0))
	_feed.present(_located(200.0))
	_feed.jump_to_recent()
	_feed.present(_located(300.0))
	_feed.jump_to_recent()
	assert_eq(_jumps.back(), Vector2(300, 0))


func test_an_alert_that_may_not_say_where_is_never_a_jump_target() -> void:
	var secret := Alert.make(AlertCatalog.Type.SUPERWEAPON_BUILT, ME, 0)
	secret.located_at(Vector3(5, 0, 5))
	assert_false(secret.has_position, "the catalog forbids locating it")
	_feed.present(secret)
	assert_eq(_toasts(), 1)
	assert_false(_feed.jump_to_recent())
	assert_eq(_jumps.size(), 0)


func test_the_same_words_again_are_counted_not_stacked() -> void:
	var floating := Alert.make(AlertCatalog.Type.ENERGY_FLOATING, ME, 0)
	_feed.present(floating)
	_feed.present(Alert.make(AlertCatalog.Type.ENERGY_FLOATING, ME, 1))
	assert_eq(_toasts(), 1)


func test_the_stack_is_capped() -> void:
	for i: int in AlertFeed.MAX_TOASTS + 3:
		_feed.present(_located(i * 1000.0))
	assert_eq(_toasts(), AlertFeed.MAX_TOASTS)


func _ready_alert(a_text: String, a_x: float) -> Alert:
	return Alert.make(AlertCatalog.Type.UNIT_READY, ME, 0, a_text).located_at(Vector3(a_x, 0, 0))


func test_completions_are_counted_on_the_toast_that_says_them() -> void:
	_feed.present(_ready_alert("Recruit ready", 0.0))
	_feed.present(_ready_alert("Badger ready", 500.0))
	_feed.present(_ready_alert("Recruit ready", 900.0))
	assert_eq(_toasts(), 2, "the Recruit toast counted the second Recruit")
	var top := _feed.get_child(0) as PanelContainer
	assert_string_contains((top.get_meta(&"label") as Label).text, "Recruit ready  ×2")
	GameSettings.set_alert_jump_scope(GameSettings.AlertJumpScope.ALL)
	_feed.jump_to_recent()
	assert_eq(_jumps.back(), Vector2(900, 0), "and points at the newest")


func test_a_completion_plays_the_generic_sound_until_its_purchase_has_one() -> void:
	var alert := _ready_alert("Recruit ready", 0.0)
	alert.purchase = &"anything"
	assert_eq(AlertFeed.sound_for(alert), AlertFeed.SOUNDS[&"complete"])


func test_by_default_the_jump_key_skips_good_news() -> void:
	_feed.present(_located(100.0))
	_feed.present(_ready_alert("Recruit ready", 900.0))
	assert_eq(GameSettings.alert_jump_scope(), GameSettings.AlertJumpScope.NEGATIVE)
	_feed.jump_to_recent()
	_feed.jump_to_recent()
	assert_eq(_jumps, [Vector2(100, 0), Vector2(100, 0)], "only the attack, twice")


func test_the_all_scope_visits_every_located_alert() -> void:
	GameSettings.set_alert_jump_scope(GameSettings.AlertJumpScope.ALL)
	_feed.present(_located(100.0))
	_feed.present(_ready_alert("Recruit ready", 900.0))
	_feed.jump_to_recent()
	_feed.jump_to_recent()
	assert_eq(_jumps, [Vector2(900, 0), Vector2(100, 0)])


func test_completions_do_not_push_attacks_out_of_the_negative_cycle() -> void:
	_feed.present(_located(100.0))
	for i: int in AlertFeed.HISTORY_SIZE * 2:
		_feed.present(_ready_alert("Unit %d ready" % i, 900.0 + i))
	assert_true(_feed.jump_to_recent())
	assert_eq(_jumps.back(), Vector2(100, 0))
