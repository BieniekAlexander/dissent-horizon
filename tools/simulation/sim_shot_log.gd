class_name SimShotLog
extends RefCounted

## Every emission the placed pieces fired during a run, who fired it, and whom it landed on: the
## record behind the `hit_rate` check (gdd/systems/scenario-scripting/simulation-tests.md
## §Counting shots). It measures the WEAPON — how many shots hit — and says nothing about
## whether anything died, which is the shooter's damage rate and another question.
##
## A shot is SETTLED once its emission has left the game; until then it may still land, so it
## is counted neither as a hit nor as a miss.

#region State
## One entry per emission, in firing order: { "group": String, "piece": String,
## "victims": Dictionary (instance id -> true), "settled": bool }.
var _shots: Array[Dictionary] = []
#endregion


#region Recording
## Record what `a_shooter`, a member of group `a_reference` placed as `a_piece`, fires from now on.
func watch(a_reference: String, a_shooter: Actor, a_piece: String) -> void:
	a_shooter.action_tracker.cued.connect(
		func(a_cue: StringName, a_source: Object) -> void:
			if a_cue == ActionTracker.CUE_EMITTED and a_source is Entity:
				_record(a_reference, a_piece, a_source as Entity)
	)


func _record(a_reference: String, a_piece: String, a_emission: Entity) -> void:
	var shot: Dictionary = {"group": a_reference, "piece": a_piece, "victims": {}, "settled": false}
	_shots.append(shot)
	var payload: Payload = Payload.of(a_emission)
	if payload != null:
		payload.paid_out.connect(
			func(a_victims: Array) -> void:
				for victim: Variant in a_victims:
					if is_instance_valid(victim):
						shot["victims"][(victim as Object).get_instance_id()] = true
		)
	a_emission.tree_exiting.connect(func() -> void: shot["settled"] = true)


#endregion


#region Queries
## Of the SETTLED shots fired by `a_reference` (narrowed to `a_piece` when given), how many landed
## on any of `a_target_ids`: Vector2i(hits, settled).
func tally(a_reference: String, a_piece: String, a_target_ids: Array) -> Vector2i:
	var hits: int = 0
	var settled: int = 0
	for shot: Dictionary in _shots:
		if shot["group"] != a_reference or (a_piece != "" and shot["piece"] != a_piece):
			continue
		if not shot["settled"]:
			continue
		settled += 1
		for id: int in a_target_ids:
			if (shot["victims"] as Dictionary).has(id):
				hits += 1
				break
	return Vector2i(hits, settled)
#endregion
