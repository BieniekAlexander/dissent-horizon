extends GutTest

## Unit tests for the simulation-spec GRAMMAR — the parser, the validator, and the folds.
##
## These belong in the suite even though simulation tests themselves do not: the parser is
## SOFTWARE, and its correctness must not move when a stat moves. What is deliberately absent
## is any test that boots an arena or asserts a matchup's outcome — that is a design question
## and lives in `sims/`, run by tools/simulation/run_sims.tscn.
## See gdd/systems/scenario-scripting/simulation-tests.md §A simulation test asks about DESIGN.
##
## Every fixture below is built here rather than read from `sims/`, for the same reason a unit
## test never asserts facts about authored content (CLAUDE.md): the shipped specs are content
## and are expected to change.

## A minimal spec that must parse clean. Two real piece ids, because piece validation is part
## of what is under test.
##
## HELD AS LINES, not as a `"""` block: YAML indents with spaces, and a space-indented line
## inside a tab-indented test file is what `test_SuiteIntegrity` looks for — it cannot tell a
## string literal from a statement, and the case it exists to catch (a file GDScript refuses
## to parse, which GUT then skips in silence) is worth more than the convenience of a block.
const VALID_LINES: Array[String] = [
	"description: a fixture",
	"setting: { kind: flat, size: 30 }",
	"given:",
	"  A:",
	"    with:",
	"      army:",
	"        of:",
	"          - { piece: an_bioLight_builder, count: 2 }",
	"        at: west",
	"        facing: east",
	"        formation: line",
	"        orders: [ { attack: { target: B.army } } ]",
	"    settings:",
	"      difficulty: MEDIUM",
	"  B:",
	"    with:",
	"      army:",
	"        of: [ { piece: cl_bioLight_antiLight } ]",
	"        at: { from: A.army, distance: 10, bearing: east }",
	"        orders: [ { move: { target: A.army } } ]",
	"run: { for: 10s, seed: 7 }",
	"expect:",
	"  - { of: B.army, check: dead }",
	"  - any:",
	"      - { of: A.army, check: alive }",
	"      - { of: A.army, check: hp_fraction, at_least: 0.5, when: always }",
]


#region Parsing a valid spec
func test_a_valid_spec_parses_without_errors() -> void:
	var spec: SimSpec = SimSpec.parse(_valid(), "fixture")
	assert_eq(spec.errors, [] as Array[String], "no validation errors")
	assert_true(spec.is_valid(), "spec reports valid")


func test_groups_are_keyed_by_qualified_reference() -> void:
	var spec: SimSpec = SimSpec.parse(_valid(), "fixture")
	assert_true(spec.groups.has("A.army"), "A.army is addressable")
	assert_true(spec.groups.has("B.army"), "B.army is addressable")
	assert_eq(spec.groups.size(), 2, "two groups, and the bare name never collides")


func test_a_group_carries_its_composition_and_count() -> void:
	var spec: SimSpec = SimSpec.parse(_valid(), "fixture")
	var group: SimSpec.Group = spec.groups["A.army"]
	assert_eq(group.total_count(), 2, "count is read")
	assert_eq(group.composition[0].piece, "an_bioLight_builder")


func test_count_defaults_to_one() -> void:
	var spec: SimSpec = SimSpec.parse(_valid(), "fixture")
	assert_eq((spec.groups["B.army"] as SimSpec.Group).total_count(), 1)


func test_commander_settings_are_read_and_default_to_passive() -> void:
	var spec: SimSpec = SimSpec.parse(_valid(), "fixture")
	assert_eq((spec.commanders["A"] as SimSpec.CommanderSettings).difficulty, "MEDIUM")
	assert_eq(
		(spec.commanders["B"] as SimSpec.CommanderSettings).difficulty,
		"PASSIVE",
		"a slot that names no difficulty does not think"
	)


func test_the_run_window_and_seed_are_read() -> void:
	var spec: SimSpec = SimSpec.parse(_valid(), "fixture")
	assert_almost_eq(spec.run_seconds, 10.0, 0.001)
	assert_eq(spec.seed_value, 7)


func test_a_spec_naming_no_seed_leaves_the_choice_to_the_runner() -> void:
	var spec: SimSpec = SimSpec.parse(_valid().replace(", seed: 7", ""), "fixture")
	assert_eq(spec.seed_value, -1, "-1 means the runner draws and records one")


#endregion


#region Orders
func test_an_entity_order_reads_its_target_group() -> void:
	var spec: SimSpec = SimSpec.parse(_valid(), "fixture")
	var order: SimSpec.Order = (spec.groups["A.army"] as SimSpec.Group).orders[0]
	assert_eq(order.command, "attack")
	assert_eq(order.target.group_ref, "B.army")
	assert_false(order.target.picks_one(), "no pick means the whole set, expanded as a queue")


func test_a_positional_order_reads_its_destination() -> void:
	var spec: SimSpec = SimSpec.parse(_valid(), "fixture")
	var order: SimSpec.Order = (spec.groups["B.army"] as SimSpec.Group).orders[0]
	assert_eq(order.command, "move")
	assert_null(order.target, "a positional command takes no entity")
	assert_eq(order.position.from_ref, "A.army")
	assert_false(order.approaches, "`target:` drives at the point, not beside it")


func test_a_pick_selector_is_accepted_on_an_order() -> void:
	var text: String = _valid().replace(
		"orders: [ { attack: { target: B.army } } ]",
		"orders: [ { attack: { target: { of: B.army, pick: nearest } } } ]"
	)
	var spec: SimSpec = SimSpec.parse(text, "fixture")
	assert_eq(spec.errors, [] as Array[String])
	var order: SimSpec.Order = (spec.groups["A.army"] as SimSpec.Group).orders[0]
	assert_true(order.target.picks_one())


func test_near_marks_a_positional_order_as_an_approach() -> void:
	var text: String = _valid().replace(
		"orders: [ { move: { target: A.army } } ]", "orders: [ { attack_move: { near: A.army } } ]"
	)
	var spec: SimSpec = SimSpec.parse(text, "fixture")
	assert_eq(spec.errors, [] as Array[String])
	var order: SimSpec.Order = (spec.groups["B.army"] as SimSpec.Group).orders[0]
	assert_true(order.approaches, "`near:` stops at the group's edge")


func test_target_and_near_together_are_refused() -> void:
	var text: String = _valid().replace(
		"{ move: { target: A.army } }", "{ move: { target: A.army, near: A.army } }"
	)
	assert_true(_has_error(SimSpec.parse(text, "f"), "aimed one way"))


func test_an_entity_command_refuses_near() -> void:
	# `attack` names an entity, and `near:` is a place — accepting it would quietly turn a
	# kill order into a walk.
	var text: String = _valid().replace(
		"{ attack: { target: B.army } }", "{ attack: { near: B.army } }"
	)
	assert_true(_has_error(SimSpec.parse(text, "f"), "names an ENTITY"))


func test_the_old_to_key_names_what_replaced_it() -> void:
	var text: String = _valid().replace("{ move: { target: A.army } }", "{ move: { to: A.army } }")
	assert_true(_has_error(SimSpec.parse(text, "f"), "renamed"))


func test_an_unknown_command_is_refused() -> void:
	var spec: SimSpec = SimSpec.parse(
		_valid().replace("{ attack: { target: B.army } }", "{ teleport: { target: B.army } }"), "f"
	)
	assert_true(_has_error(spec, "unknown command"), "errors: %s" % str(spec.errors))


func test_an_unknown_pick_is_refused() -> void:
	var text: String = _valid().replace(
		"target: B.army }", "target: { of: B.army, pick: tallest } }"
	)
	assert_true(_has_error(SimSpec.parse(text, "f"), "pick"))


#endregion


#region Expectations
func test_the_top_level_expect_list_is_an_implicit_all() -> void:
	var spec: SimSpec = SimSpec.parse(_valid(), "fixture")
	assert_eq(spec.expect_root.kind, SimSpec.ExpectNode.Kind.ALL)
	assert_eq(spec.expect_root.children.size(), 2)


func test_every_leaf_is_reachable_in_authored_order() -> void:
	var spec: SimSpec = SimSpec.parse(_valid(), "fixture")
	var leaves: Array[SimSpec.Check] = spec.expect_root.leaves()
	assert_eq(leaves.size(), 3, "one at top level plus the two under `any`")
	assert_eq(leaves[0].name, "dead")
	assert_eq(leaves[2].name, "hp_fraction")


func test_the_three_temporal_modes_are_read() -> void:
	var spec: SimSpec = SimSpec.parse(_valid(), "fixture")
	var leaves: Array[SimSpec.Check] = spec.expect_root.leaves()
	assert_eq(leaves[0].mode, SimSpec.Check.Mode.AT_END, "no `when`/`by` means at-end")
	assert_eq(leaves[2].mode, SimSpec.Check.Mode.SAFETY, "`when: always` is a safety fold")


func test_a_liveness_deadline_is_read_in_seconds() -> void:
	var text: String = _valid().replace(
		"{ of: B.army, check: dead }", "{ of: B.army, check: dead, by: 4s }"
	)
	var spec: SimSpec = SimSpec.parse(text, "f")
	var leaf: SimSpec.Check = spec.expect_root.leaves()[0]
	assert_eq(leaf.mode, SimSpec.Check.Mode.LIVENESS)
	assert_almost_eq(leaf.deadline_seconds, 4.0, 0.001)


func test_when_and_by_together_are_refused() -> void:
	var text: String = _valid().replace(
		"{ of: B.army, check: dead }", "{ of: B.army, check: dead, by: 4s, when: always }"
	)
	assert_true(_has_error(SimSpec.parse(text, "f"), "folds one way"))


func test_an_unknown_check_is_refused() -> void:
	var text: String = _valid().replace("check: dead }", "check: vibes }")
	assert_true(_has_error(SimSpec.parse(text, "f"), "unknown check"))


func test_a_pick_on_a_check_is_refused_by_name() -> void:
	# The plausible mistake: `pick` reads naturally but would silently narrow WHAT IS
	# MEASURED, where on an order it only narrows what is targeted.
	var text: String = _valid().replace("check: dead }", "check: dead, pick: nearest }")
	assert_true(_has_error(SimSpec.parse(text, "f"), "pick"))


func test_an_argument_the_check_does_not_take_is_refused() -> void:
	var text: String = _valid().replace("check: dead }", "check: dead, host: A.army }")
	assert_true(_has_error(SimSpec.parse(text, "f"), "does not take"))


func test_a_not_node_takes_exactly_one_child() -> void:
	var text: String = _valid().replace(
		"  - { of: B.army, check: dead }",
		"  - not: [ { of: B.army, check: dead }, { of: A.army, check: dead } ]"
	)
	assert_true(_has_error(SimSpec.parse(text, "f"), "exactly one child"))


#endregion


#region The boolean tree
## The tree composes VERDICTS, once, at the end — so these are pure table-driven checks over
## a hand-built tree, no simulation involved.
func test_all_requires_every_child() -> void:
	var a := _leaf("alive")
	var b := _leaf("dead")
	var node := _node(SimSpec.ExpectNode.Kind.ALL, [a, b])
	assert_true(node.resolve({a.check: true, b.check: true}))
	assert_false(node.resolve({a.check: true, b.check: false}))


func test_any_requires_one_child() -> void:
	var a := _leaf("alive")
	var b := _leaf("dead")
	var node := _node(SimSpec.ExpectNode.Kind.ANY, [a, b])
	assert_true(node.resolve({a.check: false, b.check: true}))
	assert_false(node.resolve({a.check: false, b.check: false}))


func test_not_inverts_its_child() -> void:
	var a := _leaf("alive")
	var node := _node(SimSpec.ExpectNode.Kind.NOT, [a])
	assert_false(node.resolve({a.check: true}))
	assert_true(node.resolve({a.check: false}))


func test_a_missing_verdict_reads_as_false_rather_than_crashing() -> void:
	# A leaf that never settled must not take the whole report down with it.
	var a := _leaf("alive")
	assert_false(_node(SimSpec.ExpectNode.Kind.ALL, [a]).resolve({}))


#endregion


#region Whole-spec validation
func test_an_unknown_piece_is_refused() -> void:
	var text: String = _valid().replace("an_bioLight_builder", "an_bioLight_wizard")
	assert_true(_has_error(SimSpec.parse(text, "f"), "unknown piece"))


func test_an_unknown_group_reference_is_refused() -> void:
	var text: String = _valid().replace("target: B.army }", "target: B.reserves }")
	assert_true(_has_error(SimSpec.parse(text, "f"), "unknown group"))


func test_an_unqualified_group_reference_is_refused_with_its_own_message() -> void:
	var text: String = _valid().replace("{ of: B.army, check: dead }", "{ of: army, check: dead }")
	assert_true(_has_error(SimSpec.parse(text, "f"), "unqualified"))


func test_a_group_with_no_pieces_is_refused() -> void:
	var text: String = _valid().replace("of: [ { piece: cl_bioLight_antiLight } ]", "of: []")
	assert_true(_has_error(SimSpec.parse(text, "f"), "at least one"))


func test_a_placement_cycle_is_refused() -> void:
	var text: String = _valid().replace(
		"at: west", "at: { from: B.army, distance: 5, bearing: west }"
	)
	assert_true(_has_error(SimSpec.parse(text, "f"), "cycle"))


func test_a_missing_run_window_is_refused() -> void:
	var text: String = _valid().replace("run: { for: 10s, seed: 7 }", "run: { seed: 7 }")
	assert_true(_has_error(SimSpec.parse(text, "f"), "run.for"))


func test_a_duration_without_its_unit_is_refused() -> void:
	# The thing a bare number would be mistaken for is TICKS, and a window wrong by a factor
	# of thirty is a spec that passes for the wrong reason.
	var text: String = _valid().replace("for: 10s", "for: 10")
	assert_true(_has_error(SimSpec.parse(text, "f"), "seconds"))


func test_trials_and_tolerance_are_refused_as_the_runners_business() -> void:
	var text: String = _valid().replace("run: { for: 10s", "run: { trials: 10, for: 10s")
	assert_true(_has_error(SimSpec.parse(text, "f"), "RUNNER"))


func test_a_key_under_a_slot_that_is_neither_with_nor_settings_is_refused() -> void:
	var text: String = _valid().replace(
		"    settings:\n      difficulty: MEDIUM", "    stuff:\n      x: 1"
	)
	assert_true(_has_error(SimSpec.parse(text, "f"), "neither"))


func test_commanders_under_setting_names_where_they_moved_to() -> void:
	var text: String = _valid().replace(
		"setting: { kind: flat, size: 30 }",
		"setting: { kind: flat, size: 30, commanders: { A: PASSIVE } }"
	)
	assert_true(_has_error(SimSpec.parse(text, "f"), "given.<slot>.settings"))


func test_an_unknown_difficulty_is_refused() -> void:
	var spec: SimSpec = SimSpec.parse(_valid().replace("MEDIUM", "BRUTAL"), "f")
	assert_true(_has_error(spec, "unknown difficulty"))


func test_unparseable_yaml_is_an_error_rather_than_an_empty_spec() -> void:
	# A spec that cannot be read must FAIL, never vanish from the run — the same failure mode
	# test_SuiteIntegrity guards for the suite itself.
	var spec: SimSpec = SimSpec.parse("given:\n\tA: 1\n", "f")
	assert_false(spec.is_valid())
	assert_true(_has_error(spec, "tab"), "the tab-indentation case is named: %s" % str(spec.errors))


#endregion


#region The vocabulary tables agree
func test_every_validated_check_name_has_an_implementation() -> void:
	# A check that validates and then has no implementation would abort a run halfway through
	# rather than refuse it up front, which is the one failure mode loud validation exists to
	# prevent.
	var declared: Array = SimSpec.CHECK_ARGUMENTS.keys()
	declared.sort()
	assert_eq(
		declared,
		SimCheckLibrary.implemented_names() as Array,
		"SimSpec.CHECK_ARGUMENTS and SimCheckLibrary._BUILDERS name the same checks"
	)


func test_the_piece_catalog_resolves_a_known_piece_to_a_scene() -> void:
	assert_true(SimPieceCatalog.has_piece("an_bioLight_builder"))
	assert_true(SimPieceCatalog.scene_path("an_bioLight_builder").begins_with("res://"))


func test_the_piece_catalog_does_not_invent_a_scene_for_an_unknown_piece() -> void:
	assert_false(SimPieceCatalog.has_piece("an_bioLight_wizard"))
	assert_eq(SimPieceCatalog.scene_path("an_bioLight_wizard"), "")


#endregion


#region Helpers
## The fixture as one document.
func _valid() -> String:
	return "\n".join(VALID_LINES)


func _has_error(a_spec: SimSpec, a_fragment: String) -> bool:
	for error: String in a_spec.errors:
		if error.contains(a_fragment):
			return true
	return false


func _leaf(a_name: String) -> SimSpec.ExpectNode:
	var check := SimSpec.Check.new()
	check.name = a_name
	var node := SimSpec.ExpectNode.new()
	node.kind = SimSpec.ExpectNode.Kind.LEAF
	node.check = check
	return node


func _node(a_kind: SimSpec.ExpectNode.Kind, a_children: Array) -> SimSpec.ExpectNode:
	var node := SimSpec.ExpectNode.new()
	node.kind = a_kind
	node.children.assign(a_children)
	return node


#endregion


#region Timed orders
func test_an_order_without_after_is_in_the_opening_queue() -> void:
	var spec: SimSpec = SimSpec.parse(_valid(), "fixture")
	var order: SimSpec.Order = (spec.groups["A.army"] as SimSpec.Group).orders[0]
	assert_eq(order.after_seconds, 0.0)


func test_an_order_may_be_timed_with_after() -> void:
	var text: String = _valid().replace(
		"orders: [ { move: { target: A.army } } ]",
		"orders: [ { move: { target: A.army } }, { move: { target: east }, after: 2.5s } ]"
	)
	var spec: SimSpec = SimSpec.parse(text, "fixture")
	assert_eq(spec.errors, [] as Array[String])
	var orders: Array[SimSpec.Order] = (spec.groups["B.army"] as SimSpec.Group).orders
	assert_eq(orders[1].command, "move", "`after:` is not mistaken for the command")
	assert_almost_eq(orders[1].after_seconds, 2.5, 0.001)


func test_after_names_its_unit() -> void:
	var text: String = _valid().replace(
		"{ move: { target: A.army } }", "{ move: { target: A.army }, after: 3 }"
	)
	assert_true(_has_error(SimSpec.parse(text, "f"), "seconds"))


func test_an_order_timed_past_the_window_is_refused() -> void:
	var text: String = _valid().replace(
		"{ move: { target: A.army } }", "{ move: { target: A.army }, after: 10s }"
	)
	assert_true(_has_error(SimSpec.parse(text, "f"), "never be issued"))


func test_an_order_naming_two_commands_is_refused() -> void:
	var text: String = _valid().replace(
		"{ move: { target: A.army } }", "{ move: { target: A.army }, stop: {} }"
	)
	assert_true(_has_error(SimSpec.parse(text, "f"), "single { command: argument }"))


#endregion


#region Decision-sim grammar (gdd/systems/ai/decision-sims.md)
## The valid fixture's slot A, with its `settings` block replaced by `a_settings` (lines
## indented under `settings:`).
func _with_a_settings(a_settings: String) -> String:
	return _valid().replace("    settings:\n      difficulty: MEDIUM", a_settings)


func test_a_thinking_slot_reads_its_levers() -> void:
	var spec: SimSpec = (
		SimSpec
		. parse(
			_with_a_settings(
				(
					"\n"
					. join(
						[
							"    settings:",
							"      difficulty: HARD",
							"      vision: full",
							"      energy: 1500",
							"      dominion: 20",
							"      config: { build_concurrency: 1 }",
							"      consider: { structures: [cl_bioLight_antiLight], units: [an_bioLight_builder] }",
						]
					)
				)
			),
			"f"
		)
	)
	assert_eq(spec.errors, [] as Array[String])
	var a: SimSpec.CommanderSettings = spec.commanders["A"]
	assert_true(a.vision_full)
	assert_eq(a.energy, 1500)
	assert_eq(a.dominion, 20)
	assert_eq(a.config, {"build_concurrency": 1})
	assert_eq(a.consider_structures, [&"cl_bioLight_antiLight"] as Array[StringName])
	assert_eq(a.consider_units, [&"an_bioLight_builder"] as Array[StringName])


func test_a_lever_on_an_inert_slot_is_refused() -> void:
	var text: String = _with_a_settings("    settings:\n      vision: full")
	assert_true(_has_error(SimSpec.parse(text, "f"), "PASSIVE (inert) slot"))


func test_a_config_key_that_names_no_field_is_refused() -> void:
	var text: String = _with_a_settings(
		"    settings:\n      difficulty: HARD\n      config: { no_such_field: 1 }"
	)
	assert_true(_has_error(SimSpec.parse(text, "f"), "no field"))


func test_consider_refuses_an_unknown_piece() -> void:
	var text: String = _with_a_settings(
		"    settings:\n      difficulty: HARD\n      consider: { units: [nobody] }"
	)
	assert_true(_has_error(SimSpec.parse(text, "f"), "unknown piece 'nobody'"))


func test_an_unknown_setting_is_refused() -> void:
	var text: String = _with_a_settings("    settings:\n      difficulty: HARD\n      fog: off")
	assert_true(_has_error(SimSpec.parse(text, "f"), "is not a setting"))


func test_a_bot_state_check_names_a_thinking_slot() -> void:
	var text: String = _valid().replace(
		"  - { of: B.army, check: dead }", "  - { slot: A, check: posture, is: ATTACK }"
	)
	var spec: SimSpec = SimSpec.parse(text, "f")
	assert_eq(spec.errors, [] as Array[String])
	var leaf: SimSpec.Check = spec.expect_root.leaves()[0]
	assert_eq(leaf.slot, "A")
	assert_eq(leaf.name, "posture")


func test_a_checks_near_may_be_a_place_beside_a_group() -> void:
	var text: String = _valid().replace(
		"  - { of: B.army, check: dead }",
		(
			"  - { slot: A, check: placed, piece: cl_bioLight_antiLight, "
			+ "near: { from: A.army, distance: 7, bearing: north }, within: 7 }"
		)
	)
	var spec: SimSpec = SimSpec.parse(text, "f")
	assert_eq(spec.errors, [] as Array[String])
	var near: Variant = spec.expect_root.leaves()[0].arguments["near"]
	assert_true(near is SimSpec.Placement, "parsed as a placement, not left as a mapping")
	assert_eq((near as SimSpec.Placement).from_ref, "A.army")
	assert_eq((near as SimSpec.Placement).bearing, "north")
	assert_eq((near as SimSpec.Placement).distance_units, 7.0)


func test_a_place_beside_an_unknown_group_is_refused() -> void:
	var text: String = _valid().replace(
		"  - { of: B.army, check: dead }",
		(
			"  - { slot: A, check: placed, piece: cl_bioLight_antiLight, "
			+ "near: { from: A.nobody, distance: 7, bearing: north }, within: 7 }"
		)
	)
	assert_true(_has_error(SimSpec.parse(text, "f"), "A.nobody"))


func test_a_bot_state_check_on_an_inert_slot_is_refused() -> void:
	var text: String = _valid().replace(
		"  - { of: B.army, check: dead }", "  - { slot: B, check: posture, is: ATTACK }"
	)
	assert_true(_has_error(SimSpec.parse(text, "f"), "PASSIVE (inert) and decides nothing"))


func test_a_bot_state_check_without_a_slot_is_refused() -> void:
	var text: String = _valid().replace(
		"  - { of: B.army, check: dead }", "  - { check: ordered, kind: build }"
	)
	assert_true(_has_error(SimSpec.parse(text, "f"), "names no `slot`"))


func test_an_unknown_posture_is_refused() -> void:
	var text: String = _valid().replace(
		"  - { of: B.army, check: dead }", "  - { slot: A, check: posture, is: SULK }"
	)
	assert_true(_has_error(SimSpec.parse(text, "f"), "`is` must be one of"))


func test_command_reads_its_target_and_near_arguments() -> void:
	var text: String = (
		_valid()
		. replace(
			"  - { of: B.army, check: dead }",
			"  - { of: A.army, check: command, is: MoveCommand, target: B.army, near: B.army, within: 4 }"
		)
	)
	var spec: SimSpec = SimSpec.parse(text, "f")
	assert_eq(spec.errors, [] as Array[String])
	var leaf: SimSpec.Check = spec.expect_root.leaves()[0]
	assert_eq(leaf.arguments["target"], "B.army")
	assert_eq(leaf.arguments["within"], 4)


func test_command_near_without_within_is_refused() -> void:
	var text: String = _valid().replace(
		"  - { of: B.army, check: dead }",
		"  - { of: A.army, check: command, is: MoveCommand, near: B.army }"
	)
	assert_true(_has_error(SimSpec.parse(text, "f"), "needs `within`"))


func test_needs_is_read_and_an_unknown_top_level_key_is_refused() -> void:
	var spec: SimSpec = SimSpec.parse("needs: fields\n" + _valid(), "f")
	assert_eq(spec.needs, "fields")
	assert_true(_has_error(SimSpec.parse("whatever: 1\n" + _valid(), "f"), "not a spec key"))


func test_a_spec_filed_under_bot_needs_a_thinking_slot() -> void:
	var inert: String = _valid().replace("      difficulty: MEDIUM", "      difficulty: PASSIVE")
	assert_true(_has_error(SimSpec.parse(inert, "bot/targeting/x"), "needs a thinking slot"))
	assert_true(SimSpec.parse(inert, "x").is_valid(), "a duel at the root may be all inert")

#endregion
