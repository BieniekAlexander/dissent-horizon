extends GutTest

## An emitted UNIT is handed a command rather than a flight (composition-rework §The emitted
## unit): launched at an Entity it attacks it, launched at a point it attack-moves there. The
## emitter itself never learns what a broodling is — it asks whether the emission takes orders.
##
## PATHS, not preloads (CLAUDE.md §A file-scope `preload`…).

const EMITTER_ID: int = 1
const TARGET_ID: int = 2


func _commander(a_id: int) -> Commander:
	var commander := Commander.new()
	commander.id = a_id
	add_child_autofree(commander)
	return commander


## A unit put into play the way an emitter does it: instanced and initialised, then launched.
func _emitted_unit() -> Commandable:
	var unit: Commandable = FakePieces.unit({"speed": 2.0, "weapon": {"ground": 6.0}})
	unit.initialize(null, _commander(EMITTER_ID))
	autofree(unit)
	return unit


func test_launched_at_an_entity_it_attacks_it() -> void:
	var unit: Commandable = _emitted_unit()
	var target: Commandable = FakePieces.unit({"speed": 2.0, "weapon": {"ground": 6.0}})
	target.initialize(null, _commander(TARGET_ID))
	autofree(target)
	Emitter.launch(unit, null, target)
	assert_true(unit.current_command() is Attack, "an attack order, not a flight")
	assert_eq(unit.current_command().message.target, target, "on what it was launched at")


func test_launched_at_a_point_it_attack_moves_there() -> void:
	var unit: Commandable = _emitted_unit()
	var point := Vector3(7.0, 0.0, -3.0)
	Emitter.launch(unit, null, point)
	assert_true(unit.current_command() is AttackMove, "it fights on the way")
	assert_eq(unit.current_command().message.position, point)
