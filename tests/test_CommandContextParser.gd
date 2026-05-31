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

func _make_entity(a_type: int, a_groups: PackedStringArray = PackedStringArray()) -> Entity:
	var e := Entity.new()
	e.type = a_type
	autofree(e)
	for g in a_groups:
		e.add_to_group(g)
	return e

func _add_named_child(a_parent: Node, a_name: String) -> Node:
	# The parser only ever checks has_node("Movement") for the movement/rally
	# predicates, so a bare Node with the right name is sufficient there — we
	# don't need to stand up a real Movement component script. (Production is the
	# exception now: see _add_production, since the parser reads producible_types
	# off the real component to build the train menu.)
	var n := Node.new()
	n.name = a_name
	a_parent.add_child(n)
	autofree(n)
	return n

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

## --- commands_for: empty / null cases --------------------------------------

func test_null_entity_returns_empty():
	assert_eq(CommandContextParser.commands_for(null), [])

func test_bare_entity_with_no_components_and_no_groups_returns_empty():
	# UNDEFINED type, no Movement, no Production, no group memberships —
	# nothing in RULES should fire.
	var e := _make_entity(Entity.Type.UNDEFINED)
	assert_eq(CommandContextParser.commands_for(e), [])

## --- Unit-flavored predicates ---------------------------------------------

func test_unit_with_movement_gets_movement_commands():
	# UNIT_SENTRY with both a Movement and an Inventory child stands in for a
	# generic combat unit. command_move comes from Movement; the attack-flavored
	# commands come from Inventory.
	var e := _make_entity(Entity.Type.UNIT_SENTRY, ["unit"])
	_add_named_child(e, "Movement")
	_add_named_child(e, "Inventory")
	var cmds := CommandContextParser.commands_for(e)
	assert_true(cmds.has("command_move"), "movement-bearing unit can move")
	assert_true(cmds.has("command_attack_move"), "unit can attack-move")
	assert_true(cmds.has("command_stop"), "unit can stop")
	assert_true(cmds.has("command_attack"), "unit can attack")

func test_attack_range_without_movement_still_has_combat_commands():
	# The turret-like shape: an Inventory-bearing entity with no Movement node
	# loses command_move but keeps every Inventory-flavored command — stop,
	# attack, AND attack-move (the parser couples both attack commands to the
	# Inventory predicate).
	var e := _make_entity(Entity.Type.UNIT_SENTRY, ["unit"])
	_add_named_child(e, "Inventory")
	var cmds := CommandContextParser.commands_for(e)
	assert_false(cmds.has("command_move"))
	assert_true(cmds.has("command_attack_move"))
	assert_true(cmds.has("command_stop"))
	assert_true(cmds.has("command_attack"))

## --- Structure-flavored predicates ----------------------------------------

func test_structure_with_production_gets_train_and_rally_move():
	var e := _make_entity(Entity.Type.STRUCTURE_COMPOUND, ["structure"])
	_add_named_child(e, "Production")
	var cmds := CommandContextParser.commands_for(e)
	assert_true(cmds.has("command_train"), "production-bearing structure can train")
	assert_true(cmds.has("command_move"), "structure can set a rally point (command_move)")
	# Structures without Movement should NOT advertise attack-move.
	assert_false(cmds.has("command_attack_move"))

func test_compound_advertises_only_its_train_tools():
	var e := _make_entity(Entity.Type.STRUCTURE_COMPOUND, ["structure"])
	# The Production component's producible_types is the source of truth for what
	# the structure can train.
	_add_production(e, [Entity.Type.UNIT_SENTRY, Entity.Type.UNIT_VANGUARD])
	var cmds := CommandContextParser.commands_for(e)
	assert_true(cmds.has("command_tool_sentry"))
	assert_true(cmds.has("command_tool_vanguard"))
	assert_false(cmds.has("command_tool_technician"))
	assert_false(cmds.has("command_tool_outpost"))

func test_outpost_advertises_only_technician_tool():
	var e := _make_entity(Entity.Type.STRUCTURE_OUTPOST, ["structure"])
	_add_production(e, [Entity.Type.UNIT_TECHNICIAN])
	var cmds := CommandContextParser.commands_for(e)
	assert_true(cmds.has("command_tool_technician"))
	assert_false(cmds.has("command_tool_sentry"))
	assert_false(cmds.has("command_tool_vanguard"))

## --- Technician (Anima) ----------------------------------------------------

func test_technician_has_build_ability_and_inventory_actions():
	var e := _make_entity(Entity.Type.UNIT_TECHNICIAN, ["unit"])
	_add_named_child(e, "Movement")
	_add_named_child(e, "Inventory")
	var cmds := CommandContextParser.commands_for(e)
	assert_true(cmds.has("command_ability"))
	assert_true(cmds.has("command_build"))
	assert_true(cmds.has("command_pick_up"))
	assert_true(cmds.has("command_drop_off"))
	# Still has the base unit commands.
	assert_true(cmds.has("command_attack_move"))
	assert_true(cmds.has("command_stop"))

## --- Vanguard --------------------------------------------------------------

func test_vanguard_has_launch_and_collect():
	var e := _make_entity(Entity.Type.UNIT_VANGUARD, ["unit"])
	_add_named_child(e, "Movement")
	_add_named_child(e, "Inventory")
	var cmds := CommandContextParser.commands_for(e)
	assert_true(cmds.has("command_launch"))
	assert_true(cmds.has("command_collect"))
	# Still has the base unit commands.
	assert_true(cmds.has("command_attack_move"))
	assert_true(cmds.has("command_stop"))

## --- command_available -----------------------------------------------------

func test_command_available_matches_commands_for():
	var e := _make_entity(Entity.Type.UNIT_VANGUARD, ["unit"])
	_add_named_child(e, "Movement")
	_add_named_child(e, "Inventory")
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
	var anima := _make_entity(Entity.Type.UNIT_TECHNICIAN, ["unit"])
	_add_named_child(anima, "Movement")
	var compound := _make_entity(Entity.Type.STRUCTURE_COMPOUND, ["structure"])
	_add_production(compound, [Entity.Type.UNIT_SENTRY, Entity.Type.UNIT_VANGUARD])

	var cmds := CommandContextParser.commands_for_selection([anima, compound])
	assert_true(cmds.has("command_ability"), "anima contributes ability")
	assert_true(cmds.has("command_train"), "compound contributes train")
	assert_true(cmds.has("command_tool_sentry"), "compound contributes its tools")
	assert_true(cmds.has("command_stop"), "shared unit command appears once")

func test_selection_deduplicates_shared_commands():
	# Two units of the same type — every shared command name should appear
	# exactly once in the union.
	var a := _make_entity(Entity.Type.UNIT_SENTRY, ["unit"])
	_add_named_child(a, "Movement")
	_add_named_child(a, "AttackRange")
	var b := _make_entity(Entity.Type.UNIT_SENTRY, ["unit"])
	_add_named_child(b, "Movement")
	_add_named_child(b, "AttackRange")
	var cmds := CommandContextParser.commands_for_selection([a, b])
	var occurrences := cmds.filter(func(n): return n == "command_attack_move").size()
	assert_eq(occurrences, 1, "shared command appears once in the union")

func test_selection_ignores_invalid_entries():
	var e := _make_entity(Entity.Type.UNIT_SENTRY, ["unit"])
	_add_named_child(e, "Movement")
	_add_named_child(e, "Inventory")
	# Mix in nulls and a non-Entity object; parser should skip them silently.
	var stray := Node.new()
	autofree(stray)
	var cmds := CommandContextParser.commands_for_selection([null, e, stray])
	assert_true(cmds.has("command_attack_move"))

## --- build_tools_for: the Technician Build sub-menu ------------------------

func test_technician_build_tools_are_the_buildable_structures():
	# build_tools_for mirrors Build.tool_applies_to for the Technician — the
	# structures the controller's Build sub-menu offers.
	var e := _make_entity(Entity.Type.UNIT_TECHNICIAN, ["unit"])
	var tools := CommandContextParser.build_tools_for(e)
	assert_true(tools.has("command_tool_outpost"))
	assert_true(tools.has("command_tool_dwelling"))
	assert_true(tools.has("command_tool_mine"))
	assert_true(tools.has("command_tool_lab"))
	assert_true(tools.has("command_tool_compound"))
	assert_true(tools.has("command_tool_armory"))

func test_non_builder_has_no_build_tools():
	var e := _make_entity(Entity.Type.UNIT_SENTRY, ["unit"])
	assert_eq(CommandContextParser.build_tools_for(e), [])

func test_build_tools_for_null_is_empty():
	assert_eq(CommandContextParser.build_tools_for(null), [])

func test_build_tools_stay_out_of_the_flat_command_set():
	# Build tools live behind the Build sub-menu (queried via build_tools_for),
	# NOT in the unit's base command set — otherwise they'd clutter the flat HUD
	# and the selection union. The Build entry point itself must still be there.
	var e := _make_entity(Entity.Type.UNIT_TECHNICIAN, ["unit"])
	_add_named_child(e, "Movement")
	var cmds := CommandContextParser.commands_for(e)
	assert_false(cmds.has("command_tool_outpost"), "build tools stay out of the flat command set")
	assert_true(cmds.has("command_ability"), "but the Build entry point is present")

## --- train_tools_for: production-driven menu -------------------------------

func test_train_tools_for_reads_production_component():
	var e := _make_entity(Entity.Type.STRUCTURE_COMPOUND, ["structure"])
	_add_production(e, [Entity.Type.UNIT_SENTRY])
	assert_eq(CommandContextParser.train_tools_for(e), ["command_tool_sentry"])

func test_train_tools_for_entity_without_production_is_empty():
	# A producer-less entity (e.g. a plain unit) offers no train tools.
	var e := _make_entity(Entity.Type.UNIT_SENTRY, ["unit"])
	assert_eq(CommandContextParser.train_tools_for(e), [])

func test_train_tools_for_null_is_empty():
	assert_eq(CommandContextParser.train_tools_for(null), [])

## --- Scene config: producible_types is wired in the real .tscn files -------
## These instantiate the actual structure scenes (not added to the tree) to
## prove the Production node's producible_types export survives in the inherited
## scene and that the parser surfaces the right train tools end-to-end.

func test_outpost_scene_produces_technician():
	var outpost: Node = load("res://scenes/structures/outpost.tscn").instantiate()
	autofree(outpost)
	var prod := outpost.get_node("Production") as Production
	assert_not_null(prod, "outpost.tscn has a Production node")
	assert_true(prod.can_produce(Entity.Type.UNIT_TECHNICIAN), "outpost trains technicians")
	assert_true(CommandContextParser.commands_for(outpost).has("command_tool_technician"))

func test_compound_scene_produces_sentry_and_vanguard():
	var compound: Node = load("res://scenes/structures/compound.tscn").instantiate()
	autofree(compound)
	var prod := compound.get_node("Production") as Production
	assert_not_null(prod, "compound.tscn has a Production node")
	assert_true(prod.can_produce(Entity.Type.UNIT_SENTRY), "compound trains sentries")
	assert_true(prod.can_produce(Entity.Type.UNIT_VANGUARD), "compound trains vanguards")
	assert_false(prod.can_produce(Entity.Type.UNIT_TECHNICIAN), "compound does not train technicians")
	var cmds := CommandContextParser.commands_for(compound)
	assert_true(cmds.has("command_tool_sentry"))
	assert_true(cmds.has("command_tool_vanguard"))
