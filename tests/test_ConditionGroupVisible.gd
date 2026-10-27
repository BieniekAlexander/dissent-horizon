extends GutTest

## ConditionGroupVisible: anything in a group in a commander's sight right now.

const GROUP: StringName = &"test_group_visible"

var _manager: ScenarioTriggerManager


func before_each() -> void:
	_manager = ScenarioTriggerManager.new()
	add_child_autofree(_manager)
	assert_push_warning("expected parent to be Scenario")


func _condition() -> ConditionGroupVisible:
	var condition := ConditionGroupVisible.new()
	condition.group = GROUP
	condition.commander_id = 1
	return condition


## A piece in the group, at `a_xz`.
func _member(a_xz: Vector2) -> Entity:
	var piece: Entity = autofree(FakePieces.structure())
	add_child(piece)
	piece.global_position = Vector3(a_xz.x, 0.0, a_xz.y)
	piece.add_to_group(GROUP)
	return piece


## Commander 1's fog over a 64-unit square, with nothing in sight yet.
func _fog() -> Fog:
	var fog := Fog.new()
	fog.watching_commander_id = 1
	add_child_autofree(fog)
	fog.set_physics_process(false)
	fog._configure(64, 64, Vector2.ZERO, 32.0, 32.0)
	return fog


func test_an_empty_group_is_never_seen() -> void:
	assert_false(_condition().evaluate(_manager))


func test_a_member_under_the_fog_is_not_seen() -> void:
	_fog()
	_member(Vector2(5.0, 5.0))
	assert_false(_condition().evaluate(_manager))


func test_with_no_fog_to_hide_it_a_member_is_seen() -> void:
	_member(Vector2(5.0, 5.0))
	assert_true(_condition().evaluate(_manager), "nothing hides it")


func test_an_unset_group_matches_nothing() -> void:
	_member(Vector2(5.0, 5.0))
	var condition := _condition()
	condition.group = &""
	assert_false(condition.evaluate(_manager))
