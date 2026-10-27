class_name Squad
extends RefCounted

## A squad: THE UNIT OF ORDERS. A set of units and the standing POLICY they are kept doing —
## the one mechanism the Bot's military and a mission's ScenarioTactic share, so that
## decisions are made per squad and never per unit. Who picks the policy is the decision
## side and stays separate: the Bot scores it, a mission's TacticRule authors it.
## gdd/systems/ai/squads-and-relations.md §Squads.
##
## Membership is by identity key (Entity.identity_key), holding the member; `members()` prunes
## a freed one as it reads. The dispatch loop is `tick()`: a NEW policy is issued to every member
## (a real change of posture), the SAME policy is re-issued only to a member that went idle
## (arrived, or its fight ended) or that joined since (transferred in from another squad, or
## just trained), and a member still carrying out its order is left alone. That split is what
## ScenarioTactic already did for a cluster, and what BotMilitary did for the wave; it is
## written once here.

## The squad's name, for the registry and the harness. Not unique by construction.
var name: StringName = &""
## Why the squad holds its policy, in a few words, for the debug overlay: a mission tactic writes
## its winning rule's name. Never read by a decision.
var reason: String = ""

## What the squad is kept doing, or null while it has no orders. Assigned by the decision
## side; `tick()` notices the change.
var policy: SquadPolicy = null

## Which members may be given an order right now. The Bot's military excludes a unit another
## manager has claimed (mid-fight under BotTargeting, on an errand) — it is still a member and
## rejoins when released, it is just not the military's to order this tick. The default admits
## every member, which is what a mission's cluster wants.
var eligible: Callable = Callable()

## Spawn serial → the member. By serial, the same in every run of a match (SimulationSnapshot).
var _members: Dictionary = {}
## The policy last issued, against which `policy` is compared.
var _issued: SquadPolicy = null
## Spawn serial → true for every member `_issued` has reached, so a member that joined since
## is ordered on the next tick without waiting to be idle.
var _reached: Dictionary = {}


func _init(a_name: StringName = &"") -> void:
	name = a_name
	# A method, not a lambda: a saved game names what a squad admits (StateCodec).
	eligible = _admits_every_unit


func _admits_every_unit(_a_unit: Actor) -> bool:
	return true


#region Membership
func add(a_unit: Actor) -> void:
	_members[a_unit.identity_key()] = a_unit


func add_all(a_units: Array) -> void:
	for unit: Actor in a_units:
		add(unit)


func remove(a_unit: Actor) -> void:
	_members.erase(a_unit.identity_key())


func clear() -> void:
	_members.clear()


func has(a_unit: Actor) -> bool:
	return _members.has(a_unit.identity_key())


## Make `a_units` the whole membership. For a squad whose members are defined elsewhere — a
## mission cluster is a node group — and synced in each frame.
func set_members(a_units: Array) -> void:
	_members.clear()
	add_all(a_units)


## The live members. A member whose node is gone is dropped here, which is the only pruning
## a squad does; it never asks whether a member is alive by any other route.
func members() -> Array:
	var live: Array = []
	for serial: int in _members.keys():
		var member: Variant = _members[serial]
		if not is_instance_valid(member):
			_members.erase(serial)
			continue
		live.append(member)
	return live


## The live members that are ON THE FIELD. A garrisoned member is held, not gone — it stays a
## member and rejoins on release — but it is off the tree, so it has no position to read and
## cannot take an order.
func fielded() -> Array:
	return members().filter(func(unit: Actor) -> bool: return unit.is_inside_tree())


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


## The fielded members' mean position, or ZERO when none is on the field.
func centroid() -> Vector3:
	var live: Array = fielded()
	if live.is_empty():
		return Vector3.ZERO
	var total: Vector3 = Vector3.ZERO
	for unit: Actor in live:
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
	var live: Array = fielded().filter(_takes_orders).filter(eligible)
	if live.is_empty():
		return
	if _issued == null or not policy.same_as(_issued):
		redirect()
		_issued = policy
	var to_order: Array = live.filter(
		func(unit: Actor) -> bool:
			return not _reached.has(unit.identity_key()) or unit.command_receiver.is_idle()
	)
	if to_order.is_empty():
		return
	for unit: Actor in to_order:
		_reached[unit.identity_key()] = true
	policy.issue(to_order)


## A piece that takes no orders (`commandable: false`, no Orders component) is a member that is
## never ordered, as a garrisoned one is not: there is nothing to give the order to.
static func _takes_orders(a_unit: Actor) -> bool:
	return a_unit.command_receiver != null
#endregion
