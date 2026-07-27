extends GutTest

## Regression test: CommandMessage.deep_copy() must not crash when `target` has been freed.
##
## rally_commands (Commandable.rally_commands) are long-lived templates — a rallied
## MoveCommand's target can die and be FREED long before the template is ever duplicated
## (the observed crash path: Garrison.evacuate() -> Commandable.rally_chain() ->
## MoveCommand.duplicated() -> CommandMessage.deep_copy(), when a garrison host that still
## holds a stale rally template dies and evacuates its occupants). Passing an already-freed
## Object into CommandMessage.new()'s typed `a_target: Entity` parameter crashes outright
## ("previously freed... not a subclass of the expected class") rather than quietly handing
## back null, so deep_copy() has to scrub a freed target before constructing the copy, not
## after.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_CommandMessageDeepCopy.gd -gexit

const UNIT: PackedScene = preload("res://scenes/entities/units/an/an_bioLight_builder.tscn")


func test_deep_copy_scrubs_a_freed_target_instead_of_crashing() -> void:
	var target: Commandable = UNIT.instantiate()
	add_child(target)  # freed explicitly below — not autofree, which would free it too late
	var message := CommandMessage.new(null, target, null, Vector3(3, 0, 4))

	# The same "genuinely freed, not just queue_free'd" setup test_Triggers.gd's
	# ConditionEntityKilled regression uses — is_instance_valid() only reports false once the
	# object is actually gone, which queue_free() alone does not guarantee within one frame.
	target.get_parent().remove_child(target)
	target.free()

	var copy: CommandMessage = CommandMessage.deep_copy(message)
	assert_null(copy.target, "a freed target is scrubbed rather than copied")
	assert_eq(copy.position, Vector3(3, 0, 4), "falls back to world_position once target is gone")


func test_deep_copy_still_carries_a_live_target() -> void:
	var target: Commandable = UNIT.instantiate()
	add_child_autofree(target)
	var message := CommandMessage.new(null, target)

	var copy: CommandMessage = CommandMessage.deep_copy(message)
	assert_eq(copy.target, target, "a live target is copied through as before")


## A Defend region shape is freed once its last Defend is released, while messages may still
## name it; assigning the freed node to the copy's typed field used to error.
func test_deep_copy_scrubs_a_freed_aggro_shape() -> void:
	var region := CollisionShape3D.new()
	add_child(region)
	var message := CommandMessage.new(null, null, null, Vector3(3, 0, 4))
	message.aggro_shape = region
	region.free()

	var copy: CommandMessage = CommandMessage.deep_copy(message)
	assert_null(copy.aggro_shape, "a freed region shape is scrubbed rather than copied")


func test_deep_copy_still_carries_a_live_aggro_shape() -> void:
	var region: CollisionShape3D = add_child_autofree(CollisionShape3D.new())
	var message := CommandMessage.new(null)
	message.aggro_shape = region

	assert_eq(CommandMessage.deep_copy(message).aggro_shape, region)
