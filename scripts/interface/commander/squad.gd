class_name Squad
extends RefCounted

## A squad: THE UNIT OF ORDERS. A set of units and the standing POLICY they are kept doing —
## the one mechanism the Bot's military and a mission's ScenarioTactic share, so that
## decisions are made per squad and never per unit. Who picks the policy is the decision
## side and stays separate: the Bot scores it, a mission's TacticRule authors it.
## gdd/systems/ai/squads-and-relations.md §Squads.
##
## Membership is by instance id, so a dead member needs no reference to drop; `members()`
## prunes as it reads. The dispatch loop is `tick()`: a NEW policy is issued to every member
## (a real change of posture), the SAME policy is re-issued only to a member that went idle
## (arrived, or its fight ended) or that joined since (transferred in from another squad, or
## just trained), and a member still carrying out its order is left alone. That split is what
## ScenarioTactic already did for a cluster, and what BotMilitary did for the wave; it is
## written once here.

## The squad's name, for the registry and the harness. Not unique by construction.
var name: StringName = &""

## What the squad is kept doing, or null while it has no orders. Assigned by the decision
## side; `tick()` notices the change.
var policy: SquadPolicy = null

## Which members may be given an order right now. The Bot's military excludes a unit another
## manager has claimed (mid-fight under BotTargeting, on an errand) — it is still a member and
## rejoins when released, it is just not the military's to order this tick. The default admits
## every member, which is what a mission's cluster wants.
var eligible: Callable = func(_a_unit: Commandable) -> bool: return true

## Instance id → true.
var _members: Dictionary = {}
## The policy last issued, against which `policy` is compared.
var _issued: SquadPolicy = null
## Instance id → true for every member `_issued` has reached, so a member that joined since
## is ordered on the next tick without waiting to be idle.
var _reached: Dictionary = {}


func _init(a_name: StringName = &"") -> void:
	name = a_name


#region Membership
func add(a_unit: Commandable) -> void:
	_members[a_unit.get_instance_id()] = true


func add_all(a_units: Array) -> void:
	for unit: Commandable in a_units:
		add(unit)


func remove(a_unit: Commandable) -> void:
	_members.erase(a_unit.get_instance_id())


func clear() -> void:
	_members.clear()


func has(a_unit: Commandable) -> bool:
	return _members.has(a_unit.get_instance_id())


## Make `a_units` the whole membership. For a squad whose members are defined elsewhere — a
## mission cluster is a node group — and synced in each frame.
func set_members(a_units: Array) -> void:
	_members.clear()
	add_all(a_units)


## The live members. A member whose node is gone is dropped here, which is the only pruning
## a squad does; it never asks whether a member is alive by any other route.
func members() -> Array:
	var live: Array = []
	for id: int in _members.keys():
		if not is_instance_id_valid(id):
			_members.erase(id)
			continue
		live.append(instance_from_id(id))
	return live


func size() -> int:
	return members().size()


func is_empty() -> bool:
	return members().is_empty()


## Move every member of `a_other` into this squad and return them. They are ordered on this
## squad's next tick, whatever they were doing.
func absorb(a_other: Squad) -> Array:
	var moved: Array = a_other.members()
	add_all(moved)
	a_other.clear()
	return moved


## The members' mean position, or ZERO for an empty squad.
func centroid() -> Vector3:
	var live: Array = members()
	if live.is_empty():
		return Vector3.ZERO
	var total: Vector3 = Vector3.ZERO
	for unit: Commandable in live:
		total += unit.global_position
	return total / float(live.size())


#endregion


#region Dispatch
## Forget what was issued, so the next tick issues the policy to every member again. For a
## change the policy's own comparison would not see — the same post under a new posture.
func redirect() -> void:
	_issued = null
	_reached.clear()


## The dispatch loop. See the class note.
func tick() -> void:
	if policy == null:
		return
	var live: Array = members().filter(eligible)
	if live.is_empty():
		return
	if _issued == null or not policy.same_as(_issued):
		redirect()
		_issued = policy
	var to_order: Array = live.filter(
		func(unit: Commandable) -> bool:
			return not _reached.has(unit.get_instance_id()) or unit.command_receiver.is_idle()
	)
	if to_order.is_empty():
		return
	for unit: Commandable in to_order:
		_reached[unit.get_instance_id()] = true
	policy.issue(to_order)
#endregion
