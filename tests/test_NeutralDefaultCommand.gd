extends GutTest

## RTSController._resolve_command_class: what a DEFAULT right-click (no armed hotkey)
## resolves to, per the ownership of the thing under the cursor.
##
## The rule under test: neutral / world-owned entities (commander_id 0) are never
## attacked by default — they resolve to a plain move. Only entities OWNED by another
## commander are hostile, which is exactly Entity.is_enemy_of. Attacking a neutral
## stays possible, but has to be asked for explicitly via attack-move.
##
## Both the command and the CURSOR are asserted: the cursor used to re-derive
## hostility on its own and answered "attack" for anything not player-owned, which
## would promise an attack this resolution no longer issues.

const ACTOR: Dictionary = {"speed": 2.0, "vision": 8.0, "weapon": {"ground": 6.0}}

var _actor: Commandable


func before_each() -> void:
	_actor = _spawn(ACTOR, RTSController.PLAYER_COMMANDER_ID)


## A scene instance in the tree (so @onready component refs resolve), owned by
## `a_commander_id`. Pass 0 for neutral: Ownership reports 0 when it has no
## commander at all, which is precisely the neutral/world owner.
func _spawn(a_options: Dictionary, a_commander_id: int) -> Commandable:
	var unit: Commandable = FakePieces.unit(a_options)
	if a_commander_id != 0:
		var commander: Commander = Commander.new()
		commander.id = a_commander_id
		add_child_autofree(commander)
		commander.add_child(unit)
		unit.ownership.commander = commander
	else:
		add_child_autofree(unit)
	return unit


func _resolve(a_target: Entity, a_pending: String = "") -> Variant:
	var msg: CommandMessage = CommandMessage.new(null, a_target)
	return RTSController._resolve_command_class(a_pending, _actor, msg)


func _cursor(a_target: Entity) -> Resource:
	var msg: CommandMessage = CommandMessage.new(null, a_target)
	return RTSController.cursor_evaluator(_resolve(a_target), msg)


# --- the fix ---------------------------------------------------------------


func test_neutral_target_resolves_to_a_move() -> void:
	var neutral: Commandable = _spawn(ACTOR, 0)
	assert_eq(neutral.commander_id, 0, "fixture really is neutral")
	assert_eq(
		_resolve(neutral),
		MoveCommand,
		"a default right-click on a neutral entity is a move, not an attack"
	)


func test_neutral_target_does_not_show_the_attack_cursor() -> void:
	var neutral: Commandable = _spawn(ACTOR, 0)
	assert_ne(
		_cursor(neutral),
		RTSController.ATTACK_CURSOR,
		"the cursor must not promise an attack the click won't issue"
	)


# --- what must NOT change --------------------------------------------------


func test_enemy_target_still_resolves_to_attack() -> void:
	var enemy: Commandable = _spawn(ACTOR, 2)
	assert_true(_actor.is_enemy_of(enemy), "fixture really is hostile")
	assert_eq(_resolve(enemy), Attack, "owned enemies are still attacked by default")
	assert_eq(_cursor(enemy), RTSController.ATTACK_CURSOR)


func test_attack_move_can_still_deliberately_attack_a_neutral() -> void:
	var neutral: Commandable = _spawn(ACTOR, 0)
	assert_eq(
		_resolve(neutral, "command_attack_move"),
		Attack,
		"attacking a neutral stays available as an explicit order"
	)


func test_own_unit_is_never_attacked() -> void:
	var friendly: Commandable = _spawn(ACTOR, RTSController.PLAYER_COMMANDER_ID)
	assert_ne(_resolve(friendly), Attack)


func test_empty_ground_resolves_to_a_move() -> void:
	assert_eq(_resolve(null), MoveCommand)
	assert_eq(_cursor(null), RTSController.FREE_CURSOR)
