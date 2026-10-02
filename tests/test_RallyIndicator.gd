extends GutTest

## Tests for the structure rally-point indicator's chain-selection logic
## (RTSController._rally_commands_to_draw), the hover plumbing it reads
## (CommandableCard.is_hovered_training / InfoView.hovered_training_target), and the
## scenario-timer text format (RTSController.format_scenario_time).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_RallyIndicator.gd -gexit
##
## _rally_commands_to_draw is exercised on a bare (not-in-tree) RTSController instance —
## it only reads its Commandable/hovered arguments, none of the controller's @onready
## state — same pattern test_InfoViewWiring.gd uses for API-surface checks. Structures
## mirror test_RallyQueue.gd's out-of-tree Commandable+Production wiring.


func _make_structure() -> Commandable:
	var structure := autofree(Commandable.new()) as Commandable
	var production := Production.new()
	production.producible_types = [&"fake_trainee_a"]
	structure.add_child(production)
	structure.production = production
	return structure


func _move_to(a_x: float, a_z: float) -> MoveCommand:
	return MoveCommand.new(CommandMessage.new(null, null, null, Vector3(a_x, 0.0, a_z)))


## --- _rally_commands_to_draw ---------------------------------------------------


func test_draws_the_configured_rally_when_nothing_is_hovered() -> void:
	var controller := autofree(RTSController.new()) as RTSController
	var structure := _make_structure()
	structure.rally_commands.assign([_move_to(5, 5)])
	var commands: Array = controller._rally_commands_to_draw(structure, [])
	assert_eq(commands, structure.rally_commands)


## The unhovered view answers "where will my units go", not "where is the one being built
## going". Drawing the job in progress made the line change under the player whenever a job
## started or finished, while they were trying to read the rally they were about to set.
func test_a_job_in_progress_does_not_change_the_unhovered_line() -> void:
	var controller := autofree(RTSController.new()) as RTSController
	var structure := _make_structure()
	structure.rally_commands.assign([_move_to(9, 9)])
	structure.production.enqueue(10, null, &"fake_trainee_a", [_move_to(1, 1)])
	var commands: Array = controller._rally_commands_to_draw(structure, [])
	assert_eq(
		commands,
		structure.rally_commands,
		"the configured rally, not the chain captured for the unit being trained"
	)


## A structure builds one unit at a time (see Production), so the only job a card can name
## is job 0 — the case where the hover picks a DIFFERENT job from the head no longer exists.
## What the hover still decides is that the drawn chain is that job's captured one rather
## than the structure's live rally.
## The hover is now the ONLY way to see a specific queued unit's own orders.
func test_hovering_a_job_draws_that_jobs_own_chain() -> void:
	var controller := autofree(RTSController.new()) as RTSController
	var structure := _make_structure()
	structure.rally_commands.assign([_move_to(9, 9)])
	var head_order := _move_to(1, 1)
	structure.production.enqueue(10, null, &"fake_trainee_a", [head_order])
	var commands: Array = controller._rally_commands_to_draw(structure, [structure, 0])
	assert_eq(commands, [head_order], "hovering the card draws the job's own chain")


func test_hover_on_a_different_structure_is_ignored() -> void:
	var controller := autofree(RTSController.new()) as RTSController
	var structure := _make_structure()
	var other := _make_structure()
	structure.rally_commands.assign([_move_to(9, 9)])
	structure.production.enqueue(10, null, &"fake_trainee_a", [_move_to(1, 1)])
	var commands: Array = controller._rally_commands_to_draw(structure, [other, 0])
	assert_eq(
		commands,
		structure.rally_commands,
		"the hover names a different structure, so this one draws its configured rally"
	)


## --- CommandableCard hover / InfoView.hovered_training_target ------------------


func _make_info_view() -> InfoView:
	var info := InfoView.new()
	var summary := Control.new()
	summary.name = "Summary"
	var name_label := Label.new()
	name_label.name = "NameLabel"
	var summary_cards := HFlowContainer.new()
	summary_cards.name = "Cards"
	summary.add_child(name_label)
	summary.add_child(summary_cards)
	info.add_child(summary)

	var details := Control.new()
	details.name = "Details"
	var details_cards := HFlowContainer.new()
	details_cards.name = "Cards"
	details.add_child(details_cards)
	info.add_child(details)

	add_child_autofree(info)
	return info


func test_hovered_training_target_is_empty_with_no_cards() -> void:
	var info := _make_info_view()
	assert_eq(info.hovered_training_target(), [])


func test_hovered_training_target_finds_the_hovered_card() -> void:
	var info := _make_info_view()
	var structure := _make_structure()
	var card := CommandableCard.new()
	card.bind_training(structure, 0)
	info._details_cards.add_child(card)

	card.mouse_entered.emit()
	assert_eq(info.hovered_training_target(), [structure, 0])

	card.mouse_exited.emit()
	assert_eq(info.hovered_training_target(), [])


## --- RTSController.format_scenario_time -----------------------------------------


func test_format_scenario_time_hides_hours_under_an_hour() -> void:
	assert_eq(RTSController.format_scenario_time(0), "0:00")
	assert_eq(RTSController.format_scenario_time(65), "1:05")
	assert_eq(RTSController.format_scenario_time(3599), "59:59")


func test_format_scenario_time_shows_hours_past_an_hour() -> void:
	assert_eq(RTSController.format_scenario_time(3600), "1:00:00")
	assert_eq(RTSController.format_scenario_time(3661), "1:01:01")
