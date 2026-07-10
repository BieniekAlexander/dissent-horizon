extends GutTest

## API-surface checks for the info-panel selection/evacuate wiring (tasks 3 & 4). Bare
## instances are used (not added to the tree) so @onready node-path resolution — which
## needs a full scenario for the controller and child nodes for InfoView — doesn't run;
## has_signal/has_method work regardless. The actual signal connection is made in
## RTSController._ready (guarded on _info_view) and is exercised by the real scenario.

func test_info_view_exposes_selection_signals() -> void:
	var info := InfoView.new()
	assert_true(info.has_signal("select_only_requested"), "InfoView exposes select_only_requested")
	assert_true(info.has_signal("deselect_requested"), "InfoView exposes deselect_requested")
	info.free()

func test_controller_exposes_selection_mutators() -> void:
	var controller := RTSController.new()
	assert_true(controller.has_method("select_only"), "controller has select_only")
	assert_true(controller.has_method("remove_from_selection"), "controller has remove_from_selection")
	controller.free()

func test_commandable_card_has_activated_signal() -> void:
	var card := CommandableCard.new()
	assert_true(card.has_signal("activated"), "CommandableCard exposes activated signal")
	card.free()

func test_garrison_has_single_occupant_api() -> void:
	var g := Garrison.new()
	assert_true(g.has_method("evacuate_one"), "Garrison exposes evacuate_one")
	assert_true(g.has_method("occupants"), "Garrison exposes occupants")
	assert_eq(g.occupants().size(), 0, "a fresh garrison has no occupants")
	g.free()
