class_name Liberator
extends Node

## Liberator component — the anarchical route to capitalizing on a [Shelter]'s
## population: no command, no channel, no target selection. A unit carrying this
## component converts anything within reach that is currently liberatable into
## [converted_scene], under the liberator's own commander. Walk a Warlord past a
## Terrestrial and it walks away an Irregular.
##
## WHAT is liberatable is not decided here. A convertible piece carries a [Liberatable]
## component, which holds it on `CollisionLayers.Mask.LIBERATABLE` exactly while it
## qualifies, so the reach query returns candidates and nothing else — no piece id to
## match, no ownership to re-test. This component only decides reach and rate.
##
## Reach is the parent entity's `LiberationRange` CollisionShape3D (a sibling of this
## node, resolved by name — same arrangement as `DetectionRange`); the shape is only
## ever used as query geometry, never as a live collider. Without one the component
## is inert.
##
## Conversion REPLACES the unit rather than re-flagging it: a Terrestrial has no
## weapons and no Builds, so ownership alone would not make it an Irregular. The
## original is detached and freed — which fires its `tree_exiting`, so its shelter
## unregisters it and starts producing a replacement (see Shelter.register).
##
## The recruit's first order is to follow its liberator (see _follow), so a converted
## unit falls in behind the Warlord rather than idling where the terrestrial stood.

#region Properties
## What each converted unit becomes, spawned under this liberator's commander.
## The component is inert when null.
@export var converted_scene: PackedScene

## Maximum conversions performed in one tick.
const MAX_PER_TICK: int = 4

## Cap on the reach query itself, deliberately far above [MAX_PER_TICK] and NOT the
## same number. `intersect_shape` truncates to this count BEFORE the caller sees
## anything, so a cap tight enough to double as a conversion throttle silently drops
## candidates instead of deferring them — which is how a warlord standing in a crowd
## converted nothing at all. Reaching it now takes 32 liberatable units in one circle.
const QUERY_LIMIT: int = 32
#endregion


#region Public API
## Convert up to [MAX_PER_TICK] of the liberatable units currently in reach; any
## beyond that are picked up on following ticks. Called once per physics frame from
## Commandable._update_state (same contract as DominionGenerator.tick).
func tick() -> void:
	if converted_scene == null:
		return
	var host: Commandable = get_parent() as Commandable
	if host == null or host.map == null or host.commander == null:
		return
	var reach: CollisionShape3D = _reach_shape(host)
	if reach == null or reach.shape == null:
		return
	# No exclude list: the host is not on LIBERATABLE (it carries no Liberatable), so it
	# cannot come back from its own query the way it did on the shared targeting layer.
	var found: Array[Entity] = SU.entities_within(
		host.get_world_3d(),
		host.hull(),
		reach.shape,
		reach.global_position,
		CollisionLayers.Mask.LIBERATABLE,
		[],
		QUERY_LIMIT
	)
	var converted: int = 0
	for candidate: Entity in found:
		if converted >= MAX_PER_TICK:
			break
		if not _is_liberatable(candidate):
			continue
		_liberate(host, candidate)
		converted += 1


#endregion


#region Private helpers
func _reach_shape(a_host: Commandable) -> CollisionShape3D:
	return a_host.get_node_or_null("LiberationRange") as CollisionShape3D


## The only thing still worth re-testing at the call site: that the candidate is still
## there. Everything the LIBERATABLE layer encodes (kind, neutrality) is already true of
## anything the query returned — see [Liberatable]. This is a frame-ordering guard, not
## an eligibility filter: a unit freed earlier this frame keeps answering physics
## queries until the tree flush.
func _is_liberatable(a_entity: Entity) -> bool:
	return is_instance_valid(a_entity) and not a_entity.is_queued_for_deletion()


## Swap `a_entity` for a [converted_scene] instance owned by the host's commander,
## then set the recruit following its liberator.
##
## The original is removed from the tree BEFORE the replacement is placed, so its body
## no longer counts as an obstruction when Map.add_entity picks a non-overlapping spot
## — the recruit lands where the terrestrial stood rather than being nudged aside.
func _liberate(a_host: Commandable, a_entity: Entity) -> void:
	var spot: Vector2 = VU.in_xz(a_entity.global_position)
	var parent: Node = a_entity.get_parent()
	if parent != null:
		parent.remove_child(a_entity)
	a_entity.queue_free()

	var recruit := converted_scene.instantiate() as Commandable
	if recruit == null:
		push_error("Liberator: converted_scene is not a Commandable")
		return
	a_host.map.add_entity(recruit, spot, a_host.commander)
	_follow(recruit, a_host)


## Give [a_recruit] a plain MoveCommand TARGETING its liberator, which CommandReceiver
## reads as a follow: the recruit trails the warlord, stopping once their bodies would
## touch and setting off again when it moves, and keeps the order until the player
## replaces it (or the warlord dies). So a liberated unit tags along instead of standing
## where it was converted.
##
## Issued after add_entity so the recruit's Movement is already configured for the map;
## load_destination primes the nav target, which a freshly-spawned agent otherwise
## leaves at (0, 0, 0).
func _follow(a_recruit: Commandable, a_host: Commandable) -> void:
	var follow := MoveCommand.new(CommandMessage.new(a_host.map, a_host))
	a_recruit.update_commands(follow)
	a_recruit.load_destination(follow)
#endregion
