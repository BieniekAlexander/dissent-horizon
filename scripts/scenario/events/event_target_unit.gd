class_name EventTargetUnit extends AbstractEvent

## Base class for ordnance events that act on a single friendly unit the player
## picked by clicking. The activating Ordnance only forwards the clicked world
## position (see Ordnance.activate), so the target unit is resolved here: the
## nearest commander-owned unit within SELECT_RADIUS of this event's
## global_position, optionally filtered to one Entity.Type (see _required_type).
##
## Subclasses override _required_type() (to constrain which unit types qualify) and
## execute() (to apply their effect to the unit returned by _find_target_unit).

## World-space radius around the click within which a unit qualifies as the target.
const SELECT_RADIUS: float = 3.0

## Commander whose unit this event affects. Set by the activating Ordnance before
## execute, so the same event serves the human player and any bot.
var commander_id: int = 1

## The Entity.Type a candidate must be, or null to accept any owned unit. Override
## in subclasses that only apply to a specific unit type (e.g. Dignify → Irregular).
func _required_type() -> Variant:
	return null

## Nearest commander-owned unit within SELECT_RADIUS of this event's position that
## matches _required_type(), or null if none qualifies.
func _find_target_unit(manager: ScenarioTriggerManager) -> Commandable:
	var want: Variant = _required_type()
	var pos_xz: Vector2 = VU.inXZ(global_position)
	var best: Commandable = null
	var best_dist_sq: float = SELECT_RADIUS * SELECT_RADIUS
	for node in manager.get_tree().get_nodes_in_group("unit"):
		var candidate := node as Commandable
		if candidate == null or candidate.commander_id != commander_id:
			continue
		if want != null and candidate.type != want:
			continue
		var dist_sq: float = VU.inXZ(candidate.global_position).distance_squared_to(pos_xz)
		if dist_sq <= best_dist_sq:
			best_dist_sq = dist_sq
			best = candidate
	return best
