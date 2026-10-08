extends GutTest

## A cast that acts on ONE unit is aimed at a unit, not at a point: Sanction.targets_one_unit
## recognises it from its event, `accepts_target` is the question the cursor and UseSanction
## both ask, and a cast with no accepted unit is refused BEFORE anything is spent — activate()
## returning false is what keeps the caster's charge (UseSanction.fulfill_action spends only
## on success).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_SingleUnitCast.gd -gexit

const OWN: int = 1
const FOE: int = 2

var _manager: ScenarioTriggerManager
var _commanders: Dictionary = {}


func before_each() -> void:
	_manager = ScenarioTriggerManager.new()
	add_child_autofree(_manager)
	assert_push_warning("expected parent to be Scenario")
	_commanders = {}


func _commander(a_id: int) -> Commander:
	if not _commanders.has(a_id):
		var commander := Commander.new()
		commander.id = a_id
		add_child_autofree(commander)
		_commanders[a_id] = commander
	return _commanders[a_id]


func _unit(a_commander_id: int) -> Actor:
	var unit: Actor = FakePieces.unit()
	add_child_autofree(unit)
	unit.top_level = true
	unit.ownership.commander = _commander(a_commander_id)
	return unit


## A sanction whose event is `a_event`, packed as the authored scenes are.
func _sanction_of(a_event: AbstractEvent) -> Sanction:
	var scene := PackedScene.new()
	scene.pack(a_event)
	a_event.free()
	var sanction := Sanction.new()
	sanction.sanction_name = "Test"
	sanction.needs_vision = false
	sanction.event_scene = scene
	return sanction


func test_a_unit_event_makes_a_single_unit_cast() -> void:
	assert_true(_sanction_of(EventFreeze.new()).targets_one_unit())
	assert_false(
		_sanction_of(AbstractEvent.new()).targets_one_unit(), "a cast at a point is not one"
	)


func test_the_scope_authored_on_the_event_scene_is_what_is_asked() -> void:
	var freeze_1 := EventFreeze.new()
	freeze_1.scope = EventTargetUnit.Scope.OWN
	var sanction := _sanction_of(freeze_1)
	assert_true(sanction.accepts_target(_unit(OWN), _commander(OWN)))
	assert_false(sanction.accepts_target(_unit(FOE), _commander(OWN)))


func test_a_cast_with_no_unit_is_refused_and_spends_nothing() -> void:
	var sanction := _sanction_of(EventFreeze.new())
	assert_false(
		sanction.activate(Vector3.ZERO, _manager, _commander(OWN)),
		"nothing named — refused, so UseSanction keeps the charge"
	)


func test_a_cast_on_a_unit_it_refuses_is_refused() -> void:
	var sanction := _sanction_of(EventFreeze.new())
	var enemy := _unit(FOE)
	assert_false(sanction.activate(Vector3.ZERO, _manager, _commander(OWN), null, &"", enemy))
	assert_false(enemy.is_stunned())


func test_a_cast_on_an_accepted_unit_lands_on_it() -> void:
	var sanction := _sanction_of(EventFreeze.new())
	var mine := _unit(OWN)
	assert_true(sanction.activate(Vector3.ZERO, _manager, _commander(OWN), null, &"", mine))
	assert_true(mine.is_stunned())


func test_a_target_that_died_before_the_cast_landed_is_refused() -> void:
	var sanction := _sanction_of(EventFreeze.new())
	var mine := _unit(OWN)
	mine.free()
	assert_false(sanction.activate(Vector3.ZERO, _manager, _commander(OWN), null, &"", mine))


func test_the_marker_follows_set_ability_targeted() -> void:
	var unit := _unit(OWN)
	var marker := unit.get_node("TargetIndicator") as Node3D
	assert_false(marker.visible, "hidden until an armed ability targets it")
	unit.set_ability_targeted(true)
	assert_true(marker.visible)
	unit.set_ability_targeted(false)
	assert_false(marker.visible)
