extends GutTest

## Tests for CommandContextRegistry — the Entity.Type → CommandContext map.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_CommandContextRegistry.gd

func test_every_type_resolves_to_a_context():
	for t in Entity.Type.values():
		assert_not_null(
			CommandContextRegistry.for_type(t),
			"type %s resolves to a context" % t
		)

func test_unmapped_and_generic_units_fall_back_to_base():
	var base: CommandContext = CommandContextRegistry.for_type(Entity.Type.UNDEFINED)
	# Sentry has no special command set — same context as UNDEFINED.
	assert_eq(CommandContextRegistry.for_type(Entity.Type.UNIT_SENTRY), base)
	# An int that isn't a declared enum value also falls back to base.
	assert_eq(CommandContextRegistry.for_type(99999), base)

func test_all_structure_types_share_one_context():
	var s: CommandContext = CommandContextRegistry.for_type(Entity.Type.STRUCTURE_MINE)
	for t in [
		Entity.Type.STRUCTURE_OUTPOST,
		Entity.Type.STRUCTURE_DWELLING,
		Entity.Type.STRUCTURE_LAB,
		Entity.Type.STRUCTURE_COMPOUND,
		Entity.Type.STRUCTURE_ARMORY,
	]:
		assert_eq(CommandContextRegistry.for_type(t), s, "structure types share a context")

func test_base_context_shape():
	var base: CommandContext = CommandContextRegistry.for_type(Entity.Type.UNDEFINED)
	assert_eq(base.evaluator[0].result, Attack, "first base pattern is Attack")
	assert_eq(base.evaluator[1].result, Command, "fallback base pattern is Command")
	assert_true(base.state_maping.has("command_attack_move"))
	assert_true(base.state_maping.has("command_stop"))

func test_structure_context_prepends_train_then_includes_base():
	var s: CommandContext = CommandContextRegistry.for_type(Entity.Type.STRUCTURE_MINE)
	# Structure patterns are merged ahead of the base set, so Train wins first.
	assert_eq(s.evaluator[0].result, Train, "structure resolves Train before base")
	# Base sub-contexts are still reachable.
	assert_true(s.state_maping.has("command_attack_move"))
	assert_true(s.state_maping.has("command_stop"))

func test_technician_context_keeps_base_first_and_adds_ability():
	var tech: CommandContext = CommandContextRegistry.for_type(Entity.Type.UNIT_TECHNICIAN)
	# Technician merges base FIRST, so Attack still leads the evaluator.
	assert_eq(tech.evaluator[0].result, Attack)
	assert_true(tech.state_maping.has("command_ability"), "adds Build sub-context")
	assert_true(tech.state_maping.has("command_attack_move"), "retains base sub-contexts")

func test_vanguard_context_prepends_collect_and_adds_launch():
	var vg: CommandContext = CommandContextRegistry.for_type(Entity.Type.UNIT_VANGUARD)
	assert_eq(vg.evaluator[0].result, Collect, "vanguard resolves Collect before base")
	assert_true(vg.state_maping.has("command_launch"), "adds Launch sub-context")
	assert_true(vg.state_maping.has("command_stop"), "retains base sub-contexts")
