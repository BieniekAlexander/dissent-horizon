class_name AlliancePerspective
extends RefCounted

## What one ALLIANCE knows of a piece: where it believes the piece stands, or nothing. The
## fog-limited reading a mission's condition or target pick asks for when it decides on behalf
## of a computer commander, so a scripted enemy sees the world a skirmish bot does.
## gdd/systems/scenario-scripting/tactics.md §Trigger-decided mission commanders.
##
## An alliance is named by any one member's commander id, and read across every member: their
## fog is already shared, and their blackboards are united here, so a member that joined the
## fight late still knows what its allies saw.
##   • its own and its allies' pieces — at their live position; a side knows where it stands.
##   • a piece some member BELIEVES (CommanderBlackboard) — at its last-known location, so a
##     structure scouted once stays where it was seen and a unit's sighting goes stale.
##   • anything else — at its live position while some member can see it (stealth honoured),
##     which covers neutral pieces and tokens no blackboard records; otherwise unknown.


## Where commander `commander_id`'s alliance believes `piece` stands, or null when it knows of
## no such piece.
static func position_of(
	manager: ScenarioTriggerManager, commander_id: int, piece: Node3D
) -> Variant:
	if piece == null or not is_instance_valid(piece):
		return null
	var entity := piece as Entity
	if entity != null and entity.is_on_side_of(commander_id):
		return piece.global_position
	var members: Array[Commander] = members_of(manager, commander_id)
	var id: int = entity.identity_key() if entity != null else 0
	for member: Commander in members:
		if member.blackboard != null:
			var believed: Variant = member.blackboard.last_known_location(id)
			if believed != null:
				return believed
	if _is_stealthed(entity):
		return null
	for member: Commander in members:
		if member.has_vision_at(piece.global_position):
			return piece.global_position
	return null


## A stealthed piece is unseen by every enemy whatever the fog shows (Entity.is_visible_to); the
## fog half is asked of each member's own has_vision_at, so it reads the member's own fog.
static func _is_stealthed(entity: Entity) -> bool:
	return (
		entity != null
		and entity.stealth != null
		and entity.stealth.state == Stealth.State.STEALTHED
	)


## Whether commander `commander_id`'s alliance knows of `piece` at all.
static func knows(manager: ScenarioTriggerManager, commander_id: int, piece: Node3D) -> bool:
	return position_of(manager, commander_id, piece) != null


## The live commanders of `commander_id`'s alliance, itself included. Empty for neutral or an
## id no commander has.
static func members_of(manager: ScenarioTriggerManager, commander_id: int) -> Array[Commander]:
	var result: Array[Commander] = []
	if manager == null or manager.scenario == null:
		return result
	for member_id: int in manager.scenario.alliance_of(commander_id):
		var member: Commander = manager.get_commander(member_id)
		if member != null:
			result.append(member)
	return result
