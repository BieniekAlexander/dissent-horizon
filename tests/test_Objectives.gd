extends GutTest

## Tests for the objective layer: GlobalTrigger's PENDING → ACTIVE → COMPLETE state, the
## manager's objective collection and scenario-completion check, ObjectiveChain's
## reveal-the-next-one sequencing, and the ObjectiveView checklist.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_Objectives.gd -gexit
##
## Conditions here are stubs the test flips by hand, so the sequencing is exercised without a
## Map, a Commander, or the navmesh gate the real arming path waits on.


## A condition whose truth the test sets directly, announcing the change the way a real push
## condition would.
class StubCondition extends Condition:
	var result: bool = false

	func evaluate(_a_manager: ScenarioTriggerManager) -> bool:
		return result

	## Flip and notify, driving the owning trigger's rising-edge check.
	func satisfy() -> void:
		result = true
		_last = true
		state_changed.emit()


const PAGE: PackedScene = preload("res://scenes/dialogs/welcome.tscn")
const OBJECTIVE_VIEW: PackedScene = preload("res://scenes/interface/objective_view.tscn")

var _manager: ScenarioTriggerManager
var _chain: ObjectiveChain
var _conditions: Array[StubCondition] = []


## Build a manager with a three-step chain under it, mirroring the real scene layout (chain
## is a child of the manager; steps are children of the chain). Nothing is added to the tree
## until _start(), so each test controls when the _ready cascade happens.
func before_each() -> void:
	_conditions = []
	_manager = ScenarioTriggerManager.new()
	_chain = ObjectiveChain.new()
	_chain.name = "Objectives"
	for i: int in 3:
		var step := GlobalTrigger.new()
		step.name = "Step%d" % i
		step.scope = GlobalTrigger.ObjectiveScope.PRIMARY
		step.description = "step %d" % i
		var condition := StubCondition.new()
		step.conditions = [condition]
		_conditions.append(condition)
		_chain.add_child(step)
	_manager.add_child(_chain)


func after_each() -> void:
	if _manager.simulation_clock != null:
		_manager.simulation_clock.clear()
	get_tree().paused = false
	# Tests that never call _start() leave the manager (and the chain and steps under it)
	# out of the tree, where add_child_autofree can't reach them.
	if not _manager.is_inside_tree():
		_manager.free()


## Put the manager in the tree (running both _ready cascades) and arm the triggers, skipping
## the navmesh await the real path uses — there is no Map here.
func _start() -> void:
	add_child_autofree(_manager)
	assert_push_warning("expected parent to be Scenario")
	_manager._arm_triggers()


# --- GlobalTrigger objective state --------------------------------------------

func test_a_plain_trigger_is_not_an_objective() -> void:
	var trigger := GlobalTrigger.new()
	autofree(trigger)
	assert_eq(
		trigger.scope, GlobalTrigger.ObjectiveScope.NONE,
		"machinery triggers stay out of the checklist by default"
	)
	assert_false(trigger.is_player_facing())
	assert_false(trigger.is_objective_complete(), "and never count toward completion")


func test_state_is_derived_from_enabled_and_having_fired() -> void:
	var trigger := GlobalTrigger.new()
	autofree(trigger)
	trigger.enabled = false
	assert_eq(trigger.objective_state(), GlobalTrigger.ObjectiveState.PENDING, "not revealed")
	trigger.enabled = true
	assert_eq(trigger.objective_state(), GlobalTrigger.ObjectiveState.ACTIVE, "armed")
	trigger.has_fired = true
	trigger.enabled = false
	assert_eq(trigger.objective_state(), GlobalTrigger.ObjectiveState.COMPLETE, "done")


func test_a_repeating_objective_stays_complete_after_firing() -> void:
	# A repeating trigger stays enabled after it fires; as an objective it should still tick
	# off rather than sit unchecked forever, so has_fired wins over enabled.
	var trigger := GlobalTrigger.new()
	autofree(trigger)
	trigger.enabled = true
	trigger.has_fired = true
	assert_eq(trigger.objective_state(), GlobalTrigger.ObjectiveState.COMPLETE)


func test_only_a_primary_counts_toward_completion() -> void:
	# SECONDARY is optional by definition; FAILURE is a way to LOSE, and requiring it would mean
	# the scenario could only be won by losing.
	var trigger := GlobalTrigger.new()
	autofree(trigger)
	trigger.has_fired = true
	for scope: GlobalTrigger.ObjectiveScope in [
		GlobalTrigger.ObjectiveScope.NONE,
		GlobalTrigger.ObjectiveScope.SECONDARY,
		GlobalTrigger.ObjectiveScope.FAILURE,
	]:
		trigger.scope = scope
		assert_false(trigger.counts_toward_completion(), "scope %d is not a box to tick" % scope)
	trigger.scope = GlobalTrigger.ObjectiveScope.PRIMARY
	assert_true(trigger.counts_toward_completion())
	assert_true(trigger.is_objective_complete())


# --- Manager collection -------------------------------------------------------

func test_manager_lists_only_the_flagged_triggers() -> void:
	var machinery := GlobalTrigger.new()
	machinery.name = "AmbushWave"
	machinery.conditions = [StubCondition.new()]
	_manager.add_child(machinery)
	_start()

	assert_eq(_manager.global_triggers.size(), 4, "all four are armed as triggers")
	assert_eq(_manager.objective_triggers().size(), 3, "only the scoped three are objectives")
	assert_false(machinery in _manager.objective_triggers())


func test_pending_objectives_are_hidden_from_the_player() -> void:
	_start()
	assert_eq(
		_manager.visible_objective_triggers().size(), 1,
		"an unrevealed step would spoil what's coming, so only the live one shows"
	)


# --- Scenario completion ------------------------------------------------------

func test_scenario_completes_when_every_objective_has_fired() -> void:
	_start()
	watch_signals(_manager)
	assert_false(_manager.all_objectives_complete(), "nothing done yet")

	_conditions[0].satisfy()
	_conditions[1].satisfy()
	assert_false(_manager.all_objectives_complete(), "one still outstanding")
	assert_signal_emit_count(_manager, "scenario_completed", 0)

	_conditions[2].satisfy()
	assert_true(_manager.all_objectives_complete())
	assert_signal_emit_count(_manager, "scenario_completed", 1, "announced exactly once")


func test_a_scenario_with_no_objectives_never_completes() -> void:
	# Vacuous truth would finish every plain skirmish on frame one.
	for step: GlobalTrigger in _chain.get_children():
		step.scope = GlobalTrigger.ObjectiveScope.NONE
	_start()
	watch_signals(_manager)
	for condition: StubCondition in _conditions:
		condition.satisfy()

	assert_false(_manager.all_objectives_complete(), "zero of zero is not a finished mission")
	assert_signal_emit_count(_manager, "scenario_completed", 0)


func test_unflagged_triggers_do_not_hold_up_completion() -> void:
	var machinery := GlobalTrigger.new()
	machinery.name = "AmbushWave"
	machinery.conditions = [StubCondition.new()]
	_manager.add_child(machinery)
	_start()

	for condition: StubCondition in _conditions:
		condition.satisfy()
	assert_true(
		_manager.all_objectives_complete(),
		"a spawn wave that never fired is machinery, not an unfinished task"
	)


# --- Chain sequencing ---------------------------------------------------------

func test_chain_collects_its_steps_in_order() -> void:
	_start()
	assert_eq(_chain.steps.size(), 3)
	assert_eq(_chain.steps[0].description, "step 0", "scene-tree order is chain order")
	assert_eq(_chain.steps[2].description, "step 2")


func test_only_the_first_step_starts_active() -> void:
	_start()
	assert_eq(_chain.steps[0].objective_state(), GlobalTrigger.ObjectiveState.ACTIVE)
	assert_eq(_chain.steps[1].objective_state(), GlobalTrigger.ObjectiveState.PENDING)
	assert_eq(_chain.steps[2].objective_state(), GlobalTrigger.ObjectiveState.PENDING)
	assert_eq(_chain.active_index(), 0)


func test_completing_a_step_reveals_the_next() -> void:
	_start()
	_conditions[0].satisfy()

	assert_eq(_chain.steps[0].objective_state(), GlobalTrigger.ObjectiveState.COMPLETE)
	assert_eq(_chain.steps[1].objective_state(), GlobalTrigger.ObjectiveState.ACTIVE)
	assert_eq(_chain.steps[2].objective_state(), GlobalTrigger.ObjectiveState.PENDING)
	assert_eq(_chain.active_step(), _chain.steps[1])


func test_a_pending_step_does_not_fire_early() -> void:
	# Satisfying step 2's condition before it is revealed must do nothing: a disabled trigger
	# isn't armed, so nothing is listening to that condition yet.
	_start()
	_conditions[2].satisfy()
	assert_eq(_chain.steps[2].objective_state(), GlobalTrigger.ObjectiveState.PENDING)
	assert_eq(_chain.active_index(), 0, "and the chain hasn't advanced")


func test_chain_completes_after_the_last_step() -> void:
	_start()
	watch_signals(_chain)
	for condition: StubCondition in _conditions:
		condition.satisfy()

	assert_true(_chain.is_complete())
	assert_null(_chain.active_step(), "nothing is live any more")
	assert_signal_emit_count(_chain, "chain_completed", 1)


func test_step_events_run_on_completion() -> void:
	var seen: Array[ScenarioDialog] = []
	_manager.dialog_requested.connect(func(d: ScenarioDialog) -> void: seen.append(d))
	# After _start(): the chain only populates `steps` in its own _ready. fire() reads its
	# children when it runs, so attaching the event to an already-armed step is equivalent to
	# authoring it in the scene.
	_start()
	var event := EventShowDialog.new()
	event.page = PAGE
	event.pause_simulation = false
	_chain.steps[0].add_child(event)
	_conditions[0].satisfy()

	assert_eq(seen.size(), 1, "the completed step briefed the player")
	assert_eq(seen[0].page, PAGE, "carrying the page scene it was pointed at")


# --- ObjectiveView ------------------------------------------------------------

func _bound_view() -> ObjectiveView:
	# The SCENE, not ObjectiveView.new(): the layout is authored now, and the script looks its
	# parts up by scene-unique name.
	var view: ObjectiveView = OBJECTIVE_VIEW.instantiate()
	add_child_autofree(view)
	view.bind(_manager)
	return view


func test_view_lists_only_revealed_objectives() -> void:
	_start()
	assert_eq(_bound_view().rows(), ["%s step 0" % ObjectiveView.MARK_ACTIVE])


func test_view_crosses_off_completed_objectives() -> void:
	_start()
	var view := _bound_view()
	_conditions[0].satisfy()

	assert_eq(view.rows(), [
		"%s step 0" % ObjectiveView.MARK_COMPLETE,
		"%s step 1" % ObjectiveView.MARK_ACTIVE,
	], "the finished step stays listed, ticked, and the next one appears")


func test_view_repaints_without_being_told() -> void:
	# The view subscribes to the manager, so completing an objective updates it with no
	# explicit refresh call from gameplay code.
	_start()
	var view := _bound_view()
	for condition: StubCondition in _conditions:
		condition.satisfy()
	assert_eq(view.rows().size(), 3, "every step is listed once the chain is done")
	for row: String in view.rows():
		assert_string_starts_with(row, ObjectiveView.MARK_COMPLETE)


func test_view_stays_empty_for_a_scenario_with_no_objectives() -> void:
	for step: GlobalTrigger in _chain.get_children():
		step.scope = GlobalTrigger.ObjectiveScope.NONE
	_start()
	assert_eq(_bound_view().rows(), [], "a plain skirmish shows no checklist")


func test_the_view_is_an_authored_scene_the_hud_can_place() -> void:
	# The layout lives in the scene so it can be positioned and restyled in the editor; the
	# script only decides which rows exist. Everything it drives is looked up by scene-unique
	# name, so the tree inside can be rearranged without touching code.
	var view: ObjectiveView = OBJECTIVE_VIEW.instantiate()
	add_child_autofree(view)
	assert_true(view is Control, "a Control, so it sits inside the HUD's CanvasLayer")
	assert_not_null(view.get_node_or_null("%Panel"), "the panel is authored")
	assert_not_null(view.get_node_or_null("%Rows"), "and the row container")
	assert_not_null(view.get_node_or_null("%Title"), "and the heading")
	assert_true(view.is_in_group(ObjectiveView.GROUP), "Scenario finds it by group")


func test_rows_are_duplicated_from_the_authored_template() -> void:
	# Restyling a row should be editing one node, not editing a function.
	_start()
	var view := _bound_view()
	var template: RichTextLabel = view.get_node("%RowTemplate")
	assert_false(template.visible, "the template itself never shows")

	var built: Array[Node] = []
	for child: Node in view.get_node("%Rows").get_children():
		if child != template:
			built.append(child)
	assert_eq(built.size(), 1, "one row for the one revealed objective")
	assert_true(built[0] is RichTextLabel, "duplicated from the template")
	assert_true((built[0] as RichTextLabel).bbcode_enabled, "inheriting its authored settings")


# --- Scopes -------------------------------------------------------------------

## Add a player-facing trigger straight under the manager (not the chain, so it has no
## prerequisite and is live from the first arm). Must be called before _start().
func _scoped(a_scope: GlobalTrigger.ObjectiveScope, a_text: String) -> GlobalTrigger:
	var trigger := GlobalTrigger.new()
	trigger.name = a_text.to_pascal_case()
	trigger.scope = a_scope
	trigger.description = a_text
	var condition := StubCondition.new()
	trigger.conditions = [condition]
	_conditions.append(condition)
	_manager.add_child(trigger)
	return trigger


## The rows the view actually built, in order.
func _built_rows(a_view: ObjectiveView) -> Array[RichTextLabel]:
	var result: Array[RichTextLabel] = []
	var template: RichTextLabel = a_view.get_node("%RowTemplate")
	for child: Node in a_view.get_node("%Rows").get_children():
		if child != template:
			result.append(child as RichTextLabel)
	return result


func test_the_checklist_reads_failure_then_primary_then_secondary() -> void:
	# Not scene-tree order: a failure condition the player scrolls past is one they don't know
	# about, so it goes first whatever the author's node order was.
	_scoped(GlobalTrigger.ObjectiveScope.SECONDARY, "optional")
	_scoped(GlobalTrigger.ObjectiveScope.FAILURE, "lose")
	_start()

	assert_eq(_bound_view().rows(), [
		"%s lose" % ObjectiveView.MARK_FAILURE,
		"%s step 0" % ObjectiveView.MARK_ACTIVE,
		"%s optional" % ObjectiveView.MARK_ACTIVE,
	])


func test_a_failure_condition_is_bulleted_rather_than_checkboxed() -> void:
	# There is nothing here for the player to tick off, and a checkbox would invite them to
	# read it as something to go and do.
	var failure := _scoped(GlobalTrigger.ObjectiveScope.FAILURE, "lose")
	_start()
	var view := _bound_view()
	assert_string_starts_with(view.rows()[0], ObjectiveView.MARK_FAILURE)

	_conditions[-1].satisfy()  # _scoped appended the failure's condition last
	assert_eq(failure.objective_state(), GlobalTrigger.ObjectiveState.COMPLETE, "it did fire")
	assert_string_starts_with(view.rows()[0], ObjectiveView.MARK_FAILURE, "still a bullet")
	assert_false(
		_built_rows(view)[0].text.begins_with("[s]"),
		"and never struck through — a fired failure is not an achievement"
	)


func test_row_colour_comes_from_the_scope_not_the_state() -> void:
	_scoped(GlobalTrigger.ObjectiveScope.SECONDARY, "optional")
	_scoped(GlobalTrigger.ObjectiveScope.FAILURE, "lose")
	_start()
	var view := _bound_view()
	var colors: Array[Color] = []
	for row: RichTextLabel in _built_rows(view):
		colors.append(row.get_theme_color("default_color"))
	assert_eq(colors, [view.failure_color, view.primary_color, view.secondary_color])

	# Completing the primary strikes it through but leaves it green.
	_conditions[0].satisfy()
	var done: RichTextLabel = _built_rows(view)[1]
	assert_string_starts_with(done.text, "[s]", "a finished objective is crossed out")
	assert_eq(done.get_theme_color("default_color"), view.primary_color, "and stays green")


func test_secondary_and_failure_do_not_hold_up_completion() -> void:
	_scoped(GlobalTrigger.ObjectiveScope.SECONDARY, "optional")
	_scoped(GlobalTrigger.ObjectiveScope.FAILURE, "lose")
	_start()
	watch_signals(_manager)

	for i: int in 3:
		_conditions[i].satisfy()  # the three PRIMARY chain steps
	assert_true(
		_manager.all_objectives_complete(),
		"an optional task and a way to lose are not outstanding work"
	)
	assert_signal_emit_count(_manager, "scenario_completed", 1)


func test_a_scenario_of_only_secondaries_never_completes() -> void:
	# Same guard as the no-objectives case: nothing MUST be done, so nothing is finished.
	for step: GlobalTrigger in _chain.get_children():
		step.scope = GlobalTrigger.ObjectiveScope.SECONDARY
	_start()
	for condition: StubCondition in _conditions:
		condition.satisfy()
	assert_false(_manager.all_objectives_complete())
