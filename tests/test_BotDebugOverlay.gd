extends GutTest

## Verifies the BotDebugOverlay's two gates, that it actually emits geometry for the scout
## coverage grid, and that the active category picks what it draws and reports. Rendering can't
## be asserted headlessly, so we check the generated ImmediateMesh surface count instead: >0
## means markers were drawn this frame.
##
## Boots the scout-coverage SimulationScenario (a lone bot that scouts), lets the brain build its
## managers + scout grid, then toggles the gates (the debug view + the bot-view toggle).

const SCENE: String = "res://scenes/scenarios/test/test_scout_coverage.tscn"

var _scenario: Scenario
var _overlay: BotDebugOverlay


func before_all() -> void:
	gut.error_tracker.disabled = true  # mute Godot 4.7 navmesh bring-up engine noise


func after_all() -> void:
	gut.error_tracker.disabled = false
	DebugMode.configure(false)
	Fog.active_commander_id = -1
	BotDebugOverlay.active_category = BotDebugOverlay.DEFAULT_CATEGORY


func _boot() -> void:
	_scenario = (load(SCENE) as PackedScene).instantiate()
	add_child_autofree(_scenario)
	# Let the navmesh sync and the brain build its managers + scout grid.
	for _i: int in 90:
		await get_tree().physics_frame
	_overlay = _scenario.get_node("BotDebugOverlay") as BotDebugOverlay
	assert_not_null(_overlay, "scenario created a BotDebugOverlay")


func test_overlay_draws_only_when_both_gates_open() -> void:
	await _boot()
	if _overlay == null:
		return
	var mesh: ImmediateMesh = _overlay._mesh

	# Gate the bot-view toggle to the scout bot (commander 1).
	Fog.active_commander_id = 1

	# Debug view down → nothing drawn, even with a bot selected.
	DebugMode.configure(true)
	await get_tree().process_frame
	assert_eq(mesh.get_surface_count(), 0, "nothing drawn unless the debug view is up")

	# Both gates open → scout markers drawn.
	DebugMode.toggle()
	await get_tree().process_frame
	assert_gt(mesh.get_surface_count(), 0, "scout points drawn when the view is up + bot is active")

	# Up, but the active view is the player (not a bot) → nothing.
	Fog.active_commander_id = -1
	await get_tree().process_frame
	assert_eq(mesh.get_surface_count(), 0, "nothing drawn when the active view isn't a bot")

	# Up, but the active id isn't a real bot → nothing.
	Fog.active_commander_id = 999
	await get_tree().process_frame
	assert_eq(mesh.get_surface_count(), 0, "nothing drawn for an id that isn't a bot")


## Two frames: a resumed await runs before the frame's own _process, so a state change is
## drawn by the frame after it.
func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func test_the_active_category_picks_what_is_drawn_and_reported() -> void:
	await _boot()
	if _overlay == null:
		return
	var mesh: ImmediateMesh = _overlay._mesh
	Fog.active_commander_id = 1
	DebugMode.configure(true)
	DebugMode.toggle()

	BotDebugOverlay.active_category = BotDebugOverlay.Category.SCOUTING
	await _settle()
	assert_gt(mesh.get_surface_count(), 0)
	assert_true(_overlay.readout_text().contains("Scouting"))
	assert_true(_overlay.readout_text().contains("ever seen"))

	BotDebugOverlay.active_category = BotDebugOverlay.Category.ENEMY_PICTURE
	await _settle()
	assert_true(_overlay.readout_text().contains("Enemy picture"), "a switch refreshes at once")
	assert_true(_overlay.readout_text().contains("believed:"))

	BotDebugOverlay.active_category = BotDebugOverlay.Category.OFF
	await _settle()
	assert_eq(mesh.get_surface_count(), 0, "off draws nothing")
	assert_eq(_overlay.readout_text(), "")


func test_every_category_reports_for_a_live_bot() -> void:
	await _boot()
	if _overlay == null:
		return
	Fog.active_commander_id = 1
	DebugMode.configure(true)
	DebugMode.toggle()
	for category: int in BotDebugOverlay.CATEGORY_LABELS:
		if category == BotDebugOverlay.Category.OFF:
			continue
		BotDebugOverlay.active_category = category as BotDebugOverlay.Category
		await _settle()
		var text: String = _overlay.readout_text()
		assert_true(text.contains(BotDebugOverlay.CATEGORY_LABELS[category]), text)
		assert_gt(text.split("\n").size(), 1, "%s reports something" % text)


## Ceiling on the physics frames the lone bot is given to send its first scout.
const SCOUT_DISPATCH_FRAMES: int = 1800


func test_a_dispatched_scout_reports_the_waypoint_it_was_sent_to() -> void:
	await _boot()
	if _overlay == null:
		return
	var bot: Commander = _scenario.commanders.filter(func(c: Commander) -> bool: return c.id == 1)[0]
	var scout: BotScout = (bot.get_node("BotBrain") as BotBrain).get_scout()
	var scouts: Array = []
	for _i: int in SCOUT_DISPATCH_FRAMES:
		scouts = scout.debug_scouts().filter(func(s: Dictionary) -> bool: return s["goal"] != null)
		if not scouts.is_empty():
			break
		await get_tree().physics_frame
	assert_gt(scouts.size(), 0, "the lone bot sends a scout")
	for s: Dictionary in scouts:
		assert_true(s["goal"] is Vector3)
		assert_gte(s["stalled_for"], 0.0)
