extends GutTest

## Tests for CommandContextParser — the predicate→command-name table that
## replaced CommandContextRegistry and CommandContextProvider.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_CommandContextParser.gd
##
## The parser inspects Entity instances directly (via type / has_node /
## inventory / etc.), so these tests stand up bare Entity nodes with the
## relevant signals (a `type` enum value and, where it matters, a child node
## standing in for the component the predicate checks for). Entities are NOT
## added to the scene tree — predicates only call get_node / has_node / read
## the type field, none of which require being in the tree.

## --- Helpers ---------------------------------------------------------------

func before_each() -> void:
	# The pieces these tests name are fakes, each with a train tool so the parser can offer it.
	for id: StringName in [&"fake_builder_a", &"fake_builder_b", &"fake_soldier"]:
		FakePieces.register_tool(FakePieces.tool(id, FakePieces.PLAIN, [],
			ControlBinding.ControlContext.TRAIN))


func after_each() -> void:
	FakePieces.restore_tools()


func _make_entity(a_type: StringName, a_groups: PackedStringArray = PackedStringArray()) -> Entity:
	var e := Entity.new()
	e.id = a_type
	autofree(e)
	for g in a_groups:
		e.add_to_group(g)
	return e

## A bare Node with the right name, for components whose presence alone is what the parser
## reads. Not Movement (see _add_movement) or Production (see _add_production): the parser
## reads their state.
func _add_named_child(a_parent: Node, a_name: String) -> Node:
	var n := Node.new()
	n.name = a_name
	a_parent.add_child(n)
	autofree(n)
	return n

## A real, live Movement: the parser asks whether locomotion is ACTIVE (a deployed two-form
## piece has a dormant one), which a bare Node cannot answer.
func _add_movement(a_parent: Node) -> Movement:
	var movement := Movement.new()
	movement.name = "Locomotion"
	a_parent.add_child(movement)
	autofree(movement)
	return movement

## A real `Loadout` holding one real `Weapon` — what `command_attack_move` now requires
## (CommandContextParser._is_armed). A bare Node named "Loadout" will not do any more: an
## EMPTY loadout is exactly what an unarmed vehicle carries, and the point of the predicate
## is to tell the two apart. Pass `a_armed = false` for that unarmed shape.
func _add_loadout(a_parent: Node, a_armed: bool = true) -> Loadout:
	var loadout := Loadout.new()
	loadout.name = "Loadout"
	a_parent.add_child(loadout)
	autofree(loadout)
	if a_armed:
		var weapon := Weapon.new()
		weapon.name = "Weapon"
		loadout.add_child(weapon)
		autofree(weapon)
	return loadout

## A real Abilities pool granting `a_abilities`. The parser's predicates cast the
## "Abilities" child and call grants(), so a bare Node will not do. `_rebuild` is called by
## hand because `_ready` only fires once the node is in the tree, and these test entities are
## intentionally never added to it.
func _add_abilities(a_parent: Node, a_abilities: Array) -> Abilities:
	var pool := Abilities.new()
	pool.name = "Abilities"
	var grants: Array = []
	for id in a_abilities:
		grants.append(id)
	pool.groups = [{
		"initial_charges": 1, "max_charges": 1, "cooldown_ticks": 30, "grants": grants,
	}]
	a_parent.add_child(pool)
	pool._rebuild()
	autofree(pool)
	return pool

func _add_production(a_parent: Node, a_producible_types: Array) -> Production:
	# A real Production component — the parser's train_tools_for() reads its
	# producible_types to decide which command_tool_* names the structure offers,
	# so (unlike Movement) a bare placeholder Node won't do.
	var p := Production.new()
	p.name = "Production"
	p.producible_types.assign(a_producible_types)
	a_parent.add_child(p)
	autofree(p)
	return p

func _add_builds(a_parent: Node, a_buildable_types: Array) -> Builds:
	# A real Builds component — build_tools_for() casts the "Builds" child to
	# Builds and calls can_build(), so (like Production) a bare placeholder Node
	# won't do. buildable_types is assigned directly because Builds._ready (which
	# only asserts non-emptiness) fires once in the tree, and these test entities
	# are intentionally never added to it.
	var b := Builds.new()
	b.name = "Builds"
	b.buildable_types.assign(a_buildable_types)
	a_parent.add_child(b)
	autofree(b)
	return b


## `a_count` build tools from the LIVE Tool registry.
##
## Whichever structures the docs currently define: every test using this asserts a RULE
## about build tools, never which pieces the roster ships (CLAUDE.md §A unit test does not
## assert facts about authored content). Naming pieces here is what left this file
## unparseable — and therefore silently unrun — when three of them were deleted.
func _some_build_tools(a_count: int) -> Array:
	var tools: Array = Tool.tools_in_context(ControlBinding.ControlContext.BUILD)
	assert_gt(tools.size(), a_count, "the registry has build tools to draw on")
	return tools.slice(0, a_count)

## --- commands_for: empty / null cases --------------------------------------

func test_null_entity_returns_empty():
	assert_eq(CommandContextParser.commands_for(null), [])

func test_bare_entity_with_no_components_and_no_groups_returns_empty():
	# UNDEFINED type, no Movement, no Production, no group memberships —
	# nothing in RULES should fire.
	var e := _make_entity(&"")
	assert_eq(CommandContextParser.commands_for(e), [])

## --- Unit-flavored predicates ---------------------------------------------

func test_unit_with_movement_gets_movement_commands():
	# UNIT_IRREGULAR with both a Movement and an Loadout child stands in for a
	# generic combat unit. command_move comes from Movement; the attack-flavored
	# commands come from Loadout.
	var e := _make_entity(&"fake_builder_a", ["unit"])
	_add_movement(e)
	_add_loadout(e)
	var cmds := CommandContextParser.commands_for(e)
	assert_true(cmds.has("command_move"), "movement-bearing unit can move")
	assert_true(cmds.has("command_attack_move"), "unit can attack-move")
	assert_true(cmds.has("command_stop"), "unit can stop")
	assert_true(cmds.has("command_attack"), "unit can attack")

func test_attack_range_without_movement_still_has_combat_commands():
	# The turret-like shape: an armed entity with no Movement node loses
	# command_move but keeps every combat command — stop, attack, AND attack-move.
	var e := _make_entity(&"fake_builder_a", ["unit"])
	_add_loadout(e)
	var cmds := CommandContextParser.commands_for(e)
	assert_false(cmds.has("command_move"))
	assert_true(cmds.has("command_attack_move"))
	assert_true(cmds.has("command_stop"))
	assert_true(cmds.has("command_attack"))


## ATTACK-MOVE NEEDS A WEAPON, not merely a Loadout node.
##
## An unarmed vehicle (a truck, a dominion generator) carries an EMPTY Loadout. Offering it
## an attack-move handed it an order it could never carry out — the click resolves to Attack
## as soon as it lands on a Commandable, and Attack on a weaponless actor neither acts nor
## moves, so the unit stood still holding a dead order. Crushing is not a weapon: a truck
## flattens what it drives over as a physics contact, which is not a reason to offer it an
## attack order.
func test_an_unarmed_unit_is_not_offered_attack_move():
	var e := _make_entity(&"fake_builder_a", ["unit"])
	_add_movement(e)
	_add_loadout(e, false)

	var cmds := CommandContextParser.commands_for(e)

	assert_false(cmds.has("command_attack_move"), "an empty loadout is nothing to attack with")
	assert_true(cmds.has("command_move"), "it can still be ordered to go somewhere")


func test_arming_the_same_unit_gives_it_attack_move_back():
	# The other half, so the test above is pinning the WEAPON and not the fixture.
	var e := _make_entity(&"fake_builder_a", ["unit"])
	_add_movement(e)
	_add_loadout(e, true)

	assert_true(CommandContextParser.commands_for(e).has("command_attack_move"))

## --- Structure-flavored predicates ----------------------------------------

## A stationary producer trains and does NOT advertise a move.
##
## It still ACCEPTS a bare MoveCommand as a rally — that is `Commandable._absorb_rally_commands`,
## reached through the right-click ladder, which never consults this table. What advertising
## `command_move` here bought was a GO BUTTON on a building that cannot go anywhere, and an
## ACTIVE-card command on every barracks in the game, which is what hid their training behind
## the card toggle.
func test_a_stationary_producer_trains_and_advertises_no_move():
	var e := _make_entity(&"fake_barracks", ["structure"])
	_add_named_child(e, "Production")
	var cmds := CommandContextParser.commands_for(e)
	assert_true(cmds.has("command_train"), "production-bearing structure can train")
	assert_false(cmds.has("command_move"), "it cannot go anywhere, so it offers no Go")
	# Structures without Movement should NOT advertise attack-move.
	assert_false(cmds.has("command_attack_move"))


## The other half of the same rule: a producer that CAN move reaches both cards, getting
## `command_move` from the Movement rule like anything else that moves.
func test_a_mobile_producer_still_advertises_a_move():
	var e := _make_entity(&"fake_barracks", ["unit"])
	_add_named_child(e, "Production")
	_add_movement(e)
	var cmds := CommandContextParser.commands_for(e)
	assert_true(cmds.has("command_train"), "it still trains")
	assert_true(cmds.has("command_move"), "and it can be told where to go")

func test_compound_advertises_only_its_train_tools():
	var e := _make_entity(&"fake_barracks", ["structure"])
	# The Production component's producible_types is the source of truth for what
	# the structure can train.
	_add_production(e, [&"fake_builder_a", &"fake_soldier"])
	var cmds := CommandContextParser.commands_for(e)
	assert_true(cmds.has("command_tool_fake_builder_a"))
	assert_true(cmds.has("command_tool_fake_soldier"))
	assert_false(cmds.has("command_tool_fake_builder_b"))

func test_structure_advertises_only_its_producibles():
	var e := _make_entity(&"fake_command_center", ["structure"])
	_add_production(e, [&"fake_builder_b"])
	var cmds := CommandContextParser.commands_for(e)
	assert_true(cmds.has("command_tool_fake_builder_b"))
	assert_false(cmds.has("command_tool_fake_builder_a"))
	assert_false(cmds.has("command_tool_fake_soldier"))

## --- Technician (Anima) ----------------------------------------------------

func test_technician_has_build_ability_and_inventory_actions():
	var e := _make_entity(&"fake_builder_b", ["unit"])
	_add_movement(e)
	_add_loadout(e)
	# Build capability is component-driven: command_ability/command_build are
	# advertised iff the unit carries a Builds component (the parser only checks
	# has_node here).
	_add_named_child(e, "Builds")
	# Interactions are now component-driven: a unit advertises command_interact
	# iff it carries an Interactor (the parser only checks has_node here).
	_add_named_child(e, "Interactor")
	var cmds := CommandContextParser.commands_for(e)
	assert_true(cmds.has("command_ability"))
	assert_true(cmds.has("command_build"))
	assert_true(cmds.has("command_interact"))
	# Still has the base unit commands.
	assert_true(cmds.has("command_attack_move"))
	assert_true(cmds.has("command_stop"))

## --- Vanguard --------------------------------------------------------------

func test_vanguard_has_launch_and_interact():
	var e := _make_entity(&"fake_soldier", ["unit"])
	_add_movement(e)
	_add_loadout(e)
	# command_launch is sourced from the Abilities pool, not the unit type — the unit must
	# actually be GRANTED the irradiate ability.
	_add_abilities(e, [&"irradiate"])
	# command_interact is advertised by the presence of an Interactor component.
	_add_named_child(e, "Interactor")
	var cmds := CommandContextParser.commands_for(e)
	assert_true(cmds.has("command_launch"))
	assert_true(cmds.has("command_interact"))
	# Still has the base unit commands.
	assert_true(cmds.has("command_attack_move"))
	assert_true(cmds.has("command_stop"))

## --- command_available -----------------------------------------------------

func test_command_available_matches_commands_for():
	var e := _make_entity(&"fake_soldier", ["unit"])
	_add_movement(e)
	_add_loadout(e)
	_add_abilities(e, [&"irradiate"])
	assert_true(CommandContextParser.command_available("command_launch", e))
	assert_true(CommandContextParser.command_available("command_attack_move", e))
	assert_false(CommandContextParser.command_available("command_ability", e))
	assert_false(CommandContextParser.command_available("command_train", e))

func test_command_available_on_null_returns_false():
	assert_false(CommandContextParser.command_available("command_stop", null))

## --- commands_for_selection: union semantics ------------------------------

func test_selection_union_combines_disparate_unit_types():
	# Anima + Compound: parser should expose technician-specific commands AND
	# compound-train commands in the union.
	var anima := _make_entity(&"fake_builder_b", ["unit"])
	_add_movement(anima)
	_add_named_child(anima, "Builds")
	var compound := _make_entity(&"fake_barracks", ["structure"])
	_add_production(compound, [&"fake_builder_a", &"fake_soldier"])

	var cmds := CommandContextParser.commands_for_selection([anima, compound])
	assert_true(cmds.has("command_ability"), "anima contributes ability")
	assert_true(cmds.has("command_train"), "compound contributes train")
	assert_true(cmds.has("command_tool_fake_builder_a"), "compound contributes its tools")
	assert_true(cmds.has("command_stop"), "shared unit command appears once")

func test_selection_deduplicates_shared_commands():
	# Two units of the same type — every shared command name should appear
	# exactly once in the union.
	var a := _make_entity(&"fake_builder_a", ["unit"])
	_add_movement(a)
	_add_loadout(a)
	var b := _make_entity(&"fake_builder_a", ["unit"])
	_add_movement(b)
	_add_loadout(b)
	var cmds := CommandContextParser.commands_for_selection([a, b])
	var occurrences := cmds.filter(func(n): return n == "command_attack_move").size()
	assert_eq(occurrences, 1, "shared command appears once in the union")

func test_selection_ignores_invalid_entries():
	var e := _make_entity(&"fake_builder_a", ["unit"])
	_add_movement(e)
	_add_loadout(e)
	# Mix in nulls and a non-Entity object; parser should skip them silently.
	var stray := Node.new()
	autofree(stray)
	var cmds := CommandContextParser.commands_for_selection([null, e, stray])
	assert_true(cmds.has("command_attack_move"))

## --- build_tools_for: the Technician Build sub-menu ------------------------

func test_technician_build_tools_are_the_buildable_structures():
	# build_tools_for mirrors Build.tool_applies_to: it offers exactly the tools
	# whose structure type is listed in the builder's Builds component.
	#
	# The structures come from the LIVE REGISTRY rather than being named here. This test used
	# to spell out tc_lab / tc_barracks / tc_armory; when those pieces left the docs their
	# EntityIds consts went with them, which is a PARSE error — so GUT dropped this entire
	# file from the run and still reported green (CLAUDE.md §A skipped test file is
	# invisible). What is under test is the mirroring, and the mirroring does not care which
	# structures the roster currently ships.
	var structures: Array = _some_build_tools(3)
	var e := _make_entity(&"fake_builder_b", ["unit"])
	_add_builds(e, structures.map(func(t: Tool) -> StringName: return t.type))
	var tools := CommandContextParser.tools_for(e, ControlBinding.ControlContext.BUILD)
	for t: Tool in structures:
		assert_true(tools.has(t.command_name), "%s is offered" % t.command_name)
	assert_eq(tools.size(), structures.size(), "and nothing it cannot build is")

func test_non_builder_has_no_build_tools():
	var e := _make_entity(&"fake_builder_a", ["unit"])
	assert_eq(CommandContextParser.tools_for(e, ControlBinding.ControlContext.BUILD), [])

func test_build_tools_for_null_is_empty():
	assert_eq(CommandContextParser.tools_for(null, ControlBinding.ControlContext.BUILD), [])

func test_build_tools_stay_out_of_the_flat_command_set():
	# Build tools live behind the Build sub-menu (queried via build_tools_for),
	# NOT in the unit's base command set — otherwise they'd clutter the flat HUD
	# and the selection union. The Build entry point itself must still be there.
	var e := _make_entity(&"fake_builder_b", ["unit"])
	_add_movement(e)
	_add_named_child(e, "Builds")
	var cmds := CommandContextParser.commands_for(e)
	# A LIVE tool name: naming a deleted piece here made the assertion pass for the wrong
	# reason, since a command that does not exist is absent from every set.
	var structure: Tool = _some_build_tools(1)[0]
	assert_false(cmds.has(structure.command_name), "build tools stay out of the flat command set")
	assert_true(cmds.has("command_ability"), "but the Build entry point is present")

## --- train_tools_for: production-driven menu -------------------------------

func test_train_tools_for_reads_production_component():
	var e := _make_entity(&"fake_barracks", ["structure"])
	_add_production(e, [&"fake_builder_a"])
	assert_eq(CommandContextParser.tools_for(e, ControlBinding.ControlContext.TRAIN), ["command_tool_fake_builder_a"])

func test_train_tools_for_entity_without_production_is_empty():
	# A producer-less entity (e.g. a plain unit) offers no train tools.
	var e := _make_entity(&"fake_builder_a", ["unit"])
	assert_eq(CommandContextParser.tools_for(e, ControlBinding.ControlContext.TRAIN), [])

func test_train_tools_for_null_is_empty():
	assert_eq(CommandContextParser.tools_for(null, ControlBinding.ControlContext.TRAIN), [])

## --- Production end-to-end: component → can_produce → surfaced train tool ----
## These build minimal entities carrying only a Production component (rather than
## loading live structure scenes) to prove can_produce and the parser's train-tool
## surfacing line up for a given producible_types set.

func test_technician_producer_surfaces_technician_tool():
	var producer := _make_entity(&"fake_command_center", ["structure"])
	_add_production(producer, [&"fake_builder_b"])
	assert_true(producer.get_node("Production").can_produce(&"fake_builder_b"),
		"a producer with TECHNICIAN in producible_types trains technicians")
	assert_true(CommandContextParser.commands_for(producer).has("command_tool_fake_builder_b"))

func test_irregular_and_vanguard_producer_surfaces_both_tools():
	var producer := _make_entity(&"fake_barracks", ["structure"])
	_add_production(producer, [&"fake_builder_a", &"fake_soldier"])
	var prod := producer.get_node("Production") as Production
	assert_true(prod.can_produce(&"fake_builder_a"), "produces irregulars")
	assert_true(prod.can_produce(&"fake_soldier"), "produces vanguards")
	assert_false(prod.can_produce(&"fake_builder_b"), "does not produce technicians")
	var cmds := CommandContextParser.commands_for(producer)
	assert_true(cmds.has("command_tool_fake_builder_a"))
	assert_true(cmds.has("command_tool_fake_soldier"))
