class_name BombardTargeting

## "May this commander drop a shell here?" — the one place the Colonial bombardment
## system answers that, read by the Bombard command's precondition, by its firing, and by
## the controller's cursor feedback.
##
## A Bombard's reach is NOT distance. It can hit anywhere on the map; what it needs is for
## its own side to be SPOTTING the ground, which happens two ways:
##
##   • a [Beacon] — a firing solution someone placed. Marked used by the shot fired on it,
##     and dismissed when that shell lands.
##   • a [BeaconRange] — a persistent area around a carrier (the Bombard itself, r=20; a
##     Reverence spotter aircraft, r=5). Never spent, unlimited strikes.
##
## RANGES ARE PREFERRED OVER BEACONS, and that ordering is the load-bearing part: a strike
## that falls inside a Bombard's own 20-unit bubble costs nothing, so spending a beacon
## the player walked a Recruit across the map to place — when a free solution already
## covered the spot — would be a silent waste of the more expensive resource. `source_at`
## returns null for a covered point precisely so the caller has nothing to consume.


## Whether `commander` may bombard `world_position` at all, by either route.
static func is_spotted(commander: Commander, world_position: Vector3) -> bool:
	if commander == null:
		return false
	return (
		covering_range(commander, world_position) != null
		or beacon_at(commander, world_position) != null
	)


## The Beacon a strike on `world_position` should SPEND, or null when it should spend
## none — either because a persistent range already covers the point, or because nothing
## spots it at all (in which case the strike is refused before this matters).
##
## Callers fire first and consume second: `dismiss()` frees the beacon, so reading it
## afterwards would be reading a freed node.
static func source_at(commander: Commander, world_position: Vector3) -> Beacon:
	if commander == null or covering_range(commander, world_position) != null:
		return null
	return beacon_at(commander, world_position)


## The nearest of `commander`'s beacons covering the point, or null.
static func beacon_at(commander: Commander, world_position: Vector3) -> Beacon:
	if commander == null:
		return null
	var best: Beacon = null
	var best_distance: float = INF
	for node: Node in commander.get_tree().get_nodes_in_group(Beacon.GROUP):
		var beacon: Beacon = Beacon.of(node)
		# A USED beacon already has a shell coming for it: another battery may not spend it.
		if beacon == null or beacon.is_leaving() or beacon.is_used():
			continue
		if beacon.host().commander_id != commander.id or not beacon.covers(world_position):
			continue
		var distance: float = VU.in_xz(beacon.host().global_position).distance_to(
			VU.in_xz(world_position)
		)
		if distance < best_distance:
			best_distance = distance
			best = beacon
	return best


## The first of `commander`'s BeaconRange carriers covering the point, or null.
##
## Scans the commander's own entities rather than a group: BeaconRange is a component on
## ordinary pieces, so its carriers are already the commander's children, and a carrier
## that changes hands (a hijacked Reverence) starts spotting for its new owner with no
## bookkeeping. A blueprint or a half-built Bombard is skipped — an unfinished gun spots
## nothing.
static func covering_range(commander: Commander, world_position: Vector3) -> BeaconRange:
	if commander == null:
		return null
	for child: Node in commander.get_children():
		var entity := child as Commandable
		if (
			entity == null
			or entity.is_queued_for_deletion()
			or entity.is_planned
			or not entity.is_built
		):
			continue
		var range_node := entity.get_node_or_null("BeaconRange") as BeaconRange
		if range_node != null and range_node.covers(world_position):
			return range_node
	return null
