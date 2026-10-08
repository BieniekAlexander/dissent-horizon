class_name SquadRegistry
extends RefCounted

## A commander's squads — every Squad currently being kept to a policy on its behalf, whoever
## picks the policy: the Bot's military, or a mission's ScenarioTactic running one of its
## units' clusters. One registry per Commander (`Commander.squads`), so the harness can see
## how a side's army is organised and the Bot's squad cap has something to count.

var _squads: Array = []


## A new empty squad, registered.
func create(a_name: StringName) -> Squad:
	var squad := Squad.new(a_name)
	register(squad)
	return squad


func register(a_squad: Squad) -> void:
	if not _squads.has(a_squad):
		_squads.append(a_squad)


func release(a_squad: Squad) -> void:
	_squads.erase(a_squad)


func all() -> Array:
	return _squads.duplicate()


func count() -> int:
	return _squads.size()
