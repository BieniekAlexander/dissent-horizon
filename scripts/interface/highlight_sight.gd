class_name HighlightSight
extends RefCounted

## What of an objective's marks the watching player may see, shared by the world painter
## (ScenarioHighlight) and the minimap so the two views never disagree
## (highlights-and-fog-reveal.md §Marks are gated by the fog).
##
## A place is shown where the ground is in sight; a piece is shown while it is itself shown —
## in sight — or while its snapshot is (a fixture under the fog, remembered). Unexplored ground
## hides both. With the fog lifted, or no fog to ask, everything is shown.

#region Properties
## World XZ -> whether that point is in the watcher's live sight. Invalid shows every point.
var point_in_sight: Callable = Callable()
## Entity -> whether the watcher's snapshot of it is on screen. Invalid means no snapshots.
var snapshot_shown: Callable = Callable()
#endregion


## The sight of whoever is watching `a_node`'s scenario now.
static func for_viewer(a_node: Node) -> HighlightSight:
	var out := HighlightSight.new()
	out.point_in_sight = Fog.active_sight_test(-1)
	if not out.point_in_sight.is_valid():
		return out
	var active: Variant = Fog.get_active_fog()
	var scenario: Scenario = Scenario.of(a_node) if a_node.is_inside_tree() else null
	if not (active is Fog) or scenario == null:
		return out
	var viewer_id: int = (active as Fog).viewer_commander_id()
	for commander: Commander in scenario.commanders:
		if commander.id == viewer_id and commander.blackboard != null:
			out.snapshot_shown = commander.blackboard.is_snapshot_shown
	return out


func shows_point(a_xz: Vector2) -> bool:
	return not point_in_sight.is_valid() or point_in_sight.call(a_xz)


## A piece is shown while the fog shows it, or while its remembered snapshot stands in for it.
func shows_entity(a_entity: Entity) -> bool:
	if not point_in_sight.is_valid() or a_entity.visible:
		return true
	return snapshot_shown.is_valid() and snapshot_shown.call(a_entity)
