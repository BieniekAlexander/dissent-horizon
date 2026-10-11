class_name BuildPolicy
extends SquadPolicy

## Keep a structure of `structure_type` standing at `point`: while nobody in the squad is already
## building and the site is free, the first member able to build it is ordered to (through the
## actuator's `build`, which reserves the cost). Built for a mission's tactic rule — "rebuild
## the outpost while it is down" — and shaped as a policy so the bot's economy can use it the
## day it wants a structure held at one place
## (gdd/systems/scenario-scripting/tactics.md §Trigger-decided mission commanders).

var structure_type: StringName
var point: Vector3
var _act: BotActuator


func _init(a_act: BotActuator, a_structure_type: StringName, a_point: Vector3) -> void:
	_act = a_act
	structure_type = a_structure_type
	point = a_point


func issue(a_members: Array) -> void:
	if a_members.any(func(unit: Actor) -> bool: return unit.current_command() is Build):
		return
	for unit: Actor in a_members:
		if _act.would_build(unit, structure_type, point):
			_act.build(unit, structure_type, point)
			return


func same_as(a_other: SquadPolicy) -> bool:
	return (
		a_other is BuildPolicy
		and (a_other as BuildPolicy).structure_type == structure_type
		and (a_other as BuildPolicy).point == point
	)


func kind() -> StringName:
	return &"build"


func destination() -> Variant:
	return point
