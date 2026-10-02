extends GutTest

## The BUILD sub-menu for a selection that is only PARTLY builders.
##
## Two halves, and they had drifted apart. The MENU asked selection[0] alone, so the same
## pair of units offered structures or nothing depending on which was clicked first — while
## the Build BUTTON was on show either way, since that comes from the union across the whole
## selection. The ISSUE half then had no per-actor gate at all: every other check Build makes
## (placement, price, tech) is commander-wide, so a soldier standing in a mixed selection
## passed them all and was handed a Build it has no Builds component to carry out.
##
## Both halves are now the same rule — any member can, and only the members that can
## receive it. See CommandContextParser.tools_for_selection and Build.meets_precondition.
##
## PATHS, not preloads: a file-scope preload of an entity scene fires Tool's static registry
## initialiser at PARSE time and makes Tool.for_name return null for the whole run (see
## CLAUDE.md). This file sorts near the front of the directory, so it would be the one that
## poisons it.

## A piece that builds (whatever the registry's first build tool is) and one that cannot.
const RECRUIT: Dictionary = {"speed": 2.0, "weapon": {"ground": 6.0}}
var SERVANT: Dictionary:
	get:
		return {"speed": 2.0, "builds": [FakePieces.a_buildable_type()]}

const PLAYER: int = 1


func _commander() -> Commander:
	var c := Commander.new()
	c.id = PLAYER
	add_child_autofree(c)
	return c


## A live unit. Ownership is assigned directly rather than through initialize(), so no Map
## is needed; entering the tree is what resolves its components.
func _unit(a_options: Dictionary) -> Commandable:
	var u: Commandable = FakePieces.unit(a_options)
	add_child_autofree(u)
	u.ownership.commander = _commander()
	return u


func _build_tools(a_selection: Array) -> Array:
	return CommandContextParser.tools_for_selection(
		a_selection, ControlBinding.ControlContext.BUILD
	)


func test_a_builder_alone_offers_its_structures() -> void:
	assert_gt(_build_tools([_unit(SERVANT)]).size(), 0, "a builder lists what it can build")


func test_a_selection_with_no_builder_offers_nothing() -> void:
	assert_eq(_build_tools([_unit(RECRUIT)]).size(), 0)


func test_the_menu_does_not_depend_on_which_unit_was_selected_first() -> void:
	var servant: Commandable = _unit(SERVANT)
	var recruit: Commandable = _unit(RECRUIT)
	var expected: Array = _build_tools([servant])
	assert_gt(expected.size(), 0, "guards the fixture")
	assert_eq(_build_tools([servant, recruit]), expected, "builder picked first")
	assert_eq(
		_build_tools([recruit, servant]),
		expected,
		"non-builder picked first — the menu must not depend on click order"
	)


func test_the_union_is_deduplicated() -> void:
	var one: Commandable = _unit(SERVANT)
	var two: Commandable = _unit(SERVANT)
	assert_eq(
		_build_tools([one, two]),
		_build_tools([one]),
		"two builders of a kind offer one menu, not two"
	)


func test_the_build_order_is_refused_by_a_non_builder() -> void:
	var servant: Commandable = _unit(SERVANT)
	var recruit: Commandable = _unit(RECRUIT)
	var tools: Array = _build_tools([servant])
	assert_gt(tools.size(), 0, "guards the fixture")
	var message := CommandMessage.new(null, null)
	message.tool = Tool.for_name(tools[0])
	assert_ne(
		Build.meets_precondition(recruit, message),
		MoveCommand.PreconditionFailureCause.NONE,
		"a soldier cannot raise a building, whatever else is true"
	)


func test_a_build_with_no_tool_chosen_is_still_pending_not_refused() -> void:
	# The per-actor gate must not swallow the "you haven't picked a structure yet" state,
	# which is what keeps the sub-menu open instead of flashing an error at the player.
	assert_eq(
		Build.meets_precondition(_unit(RECRUIT), CommandMessage.new(null, null)),
		MoveCommand.PreconditionFailureCause.COMMAND_PENDING_TOOL
	)
