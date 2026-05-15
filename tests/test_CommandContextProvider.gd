extends GutTest

## Tests for the CommandContextProvider component.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_CommandContextProvider.gd

## A parent node that exposes get_command_context() — what the provider expects
## of any well-formed parent entity.
class FakeProvidingParent:
	extends Node
	var _ctx: CommandContext = CommandContext.new([])
	func get_command_context() -> CommandContext:
		return _ctx

## A parent that doesn't implement get_command_context — what the provider
## should treat as "no contribution" rather than crashing.
class FakeBareParent:
	extends Node

func test_orphan_provider_returns_null_context():
	# No parent in tree → no get_command_context to call → NULL sentinel.
	var p := CommandContextProvider.new()
	add_child_autofree(p)
	# add_child_autofree parents to the test scene root (a Node without
	# get_command_context), so this exercises the "parent lacks method" branch.
	assert_eq(p.get_context(), CommandContext.NULL)

func test_provider_delegates_to_parent_get_command_context():
	var parent := FakeProvidingParent.new()
	add_child_autofree(parent)
	var p := CommandContextProvider.new()
	parent.add_child(p)
	assert_eq(p.get_context(), parent._ctx, "provider returns parent's context")

func test_parent_without_get_command_context_returns_null():
	var parent := FakeBareParent.new()
	add_child_autofree(parent)
	var p := CommandContextProvider.new()
	parent.add_child(p)
	assert_eq(p.get_context(), CommandContext.NULL)
