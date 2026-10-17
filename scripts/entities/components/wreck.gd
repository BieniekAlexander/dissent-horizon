class_name Wreck
extends Node

## The WRECK facet: a token left where a grounded vehicle was destroyed, standing for a fixed
## time, which an infantry unit can scavenge to upgrade its weapon (Interaction.Type.SCAVENGE).
## Neutral, uncommandable and undamageable; one scavenge consumes it.
## Rules: gdd/systems/combat/scavenging.md.

## The token every grounded vehicle leaves behind. The wreck's own doc
## (gdd/factions/neutral/tokens/nt_wreck.md) is primary; the scene is the importer's.
const WRECK_SCENE_PATH: String = "res://scenes/entities/tokens/nt/nt_wreck.tscn"

## How long the wreck stands before it leaves play, in seconds. Set by the spec importer from
## the doc's `wreck: {lifespan: …}`; read when the wreck is placed, to attach its Lifespan.
@export var lifespan_seconds: float = 30.0

## Set by the scavenge that consumes this wreck, so a second scavenger finishing on the same
## tick (or a stale order) finds nothing left.
var _is_consumed: bool = false

static var _wreck_scene: PackedScene = null


func host() -> Entity:
	return get_parent() as Entity


static func of(a_node: Variant) -> Wreck:
	if a_node == null or not is_instance_valid(a_node) or not (a_node is Node):
		return null
	return (a_node as Node).get_node_or_null("Wreck") as Wreck


#region Public API
## Whether a scavenge can still take this wreck.
func is_available() -> bool:
	return not _is_consumed and not host().is_queued_for_deletion()


## Take the wreck: it leaves play at once (an expiry, not a death — nothing is destroyed).
func consume() -> void:
	if _is_consumed:
		return
	_is_consumed = true
	host().expire()


## Whether `a_piece` leaves a wreck when it is destroyed: a GROUNDED VEHICLE — a mobile MECH
## unit that is not an aircraft. Infantry, structures, aircraft, emissions and planted charges
## leave nothing.
static func leaves_wreck(a_piece: Entity) -> bool:
	return (
		a_piece != null
		and a_piece.locomotion_component != null
		and a_piece.aerial == null
		and a_piece.defense != null
		and a_piece.defense.frame_type == Defense.FrameType.MECH
		and PlantedCharge.of(a_piece) == null
		and not a_piece.is_in_group(&"emission")
	)


## Leave a wreck where `a_piece` stands, owned by the neutral commander, when the piece is one
## that leaves one (leaves_wreck) and is still in the world — a vehicle that dies inside a
## transport leaves nothing. Called from the death chokepoint, while the piece's map and
## position are still valid.
static func leave_for(a_piece: Entity) -> Entity:
	if not leaves_wreck(a_piece) or a_piece.map == null or not a_piece.is_inside_tree():
		return null
	if _wreck_scene == null:
		_wreck_scene = load(WRECK_SCENE_PATH) as PackedScene
	return place(a_piece, _neutral_commander(a_piece), _wreck_scene)


## Put a wreck made from `a_scene` into play where `a_piece` stands, under `a_owner`, standing
## for its Wreck's lifespan. The half of leave_for that does not decide whether, or whose.
static func place(a_piece: Entity, a_owner: Commander, a_scene: PackedScene) -> Entity:
	if a_owner == null or a_scene == null or a_piece.map == null:
		return null
	var wreck: Entity = a_scene.instantiate() as Entity
	if wreck == null:
		return null
	var facet: Wreck = Wreck.of(wreck)
	if facet != null:
		Lifespan.attach(wreck, facet.lifespan_seconds)
	a_piece.map.add_entity(wreck, VU.in_xz(a_piece.global_position), a_owner)
	return wreck


#endregion


#region Private helpers
## The world's commander (id 0), found through the dying piece's scenario.
static func _neutral_commander(a_piece: Entity) -> Commander:
	var scenario: Scenario = Scenario.of(a_piece)
	return scenario.commander_by_id(0) if scenario != null else null
#endregion
