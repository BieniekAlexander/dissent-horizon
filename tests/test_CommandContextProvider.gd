extends GutTest

## Tests for the CommandContextProvider component.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_CommandContextProvider.gd
##
## The provider resolves its context from CommandContextRegistry keyed by the
## parent's Entity.Type. A parent that isn't an Entity (or no parent) means the
## entity doesn't participate in command selection at all → NULL sentinel.

## A bare Node parent — stands in for "not an Entity" (and orphan, since the
## test scene root is also a plain Node).
class FakeBareParent:
	extends Node

func test_orphan_provider_returns_null_context():
	# Parented to the test scene root (a plain Node, not an Entity) → NULL.
	var p := CommandContextProvider.new()
	add_child_autofree(p)
	assert_eq(p.get_context(), CommandContext.NULL)

func test_non_entity_parent_returns_null():
	var parent := FakeBareParent.new()
	add_child_autofree(parent)
	var p := CommandContextProvider.new()
	parent.add_child(p)
	assert_eq(p.get_context(), CommandContext.NULL)

func test_entity_parent_resolves_context_by_type():
	# Not added to the tree so Entity._ready never runs; the provider only
	# needs get_parent()/type, neither of which requires being in the tree.
	var e := Entity.new()
	autofree(e)
	e.type = Entity.Type.STRUCTURE_MINE
	var p := CommandContextProvider.new()
	e.add_child(p)
	autofree(p)
	assert_eq(
		p.get_context(),
		CommandContextRegistry.for_type(Entity.Type.STRUCTURE_MINE),
		"provider returns the registry context for its parent's type"
	)
