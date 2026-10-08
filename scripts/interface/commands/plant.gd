class_name Plant
extends MoveCommand

## Plant a charge: walk into reach of the ordered point or piece, work on it for a while, and
## leave a charge there (PlantedCharge) — riding on the piece when it is one that can carry it
## (a MECH unit or structure, whoever's), standing on the ground otherwise. Spends the
## planter's one Plant charge, which stays spent until the charge it made leaves play.
## gdd/systems/combat/planted-explosives.md.

## The `kind: AbilityDefinition` doc this command is the verb of.
const ABILITY_ID: StringName = PlantedCharge.PLANT_ABILITY

## The piece a plant puts down.
const CHARGE_SCENE_PATH: String = "res://scenes/entities/units/an/an_plantedCharge.tscn"

## Working time on a piece, in ticks per point of its current hp — a tougher target takes
## longer to rig — and on bare ground, where there is no hp to scale by.
##
## CONSTANTS rather than doc keys for the reason Spot's are: exactly one piece plants. Carried
## over unchanged from the PLANT interaction this replaced, reach included — a reach with some
## radius, because RVO keeps bodies apart and a touch-only reach chases a moving tank forever.
const TICKS_PER_TARGET_HP: float = 0.2
const GROUND_CHANNEL_TICKS: int = 30
const REACH: float = 1.5


#region Preconditions
## A unit granted Plant with its charge ready. Where it plants is not a precondition's
## business: a piece that cannot carry a charge has one planted at its feet instead.
static func meets_precondition(
	actor: Actor, _message: CommandMessage
) -> MoveCommand.PreconditionFailureCause:
	var pool := actor.get_node_or_null("Abilities") as Abilities if actor != null else null
	if pool == null or not pool.grants(ABILITY_ID):
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	if not pool.is_ready(ABILITY_ID):
		return PreconditionFailureCause.ABILITY_NO_CHARGES
	return PreconditionFailureCause.NONE


static func default_cast_arity(_message: CommandMessage) -> CastArity:
	return AbilityCatalog.cast_arity_of(ABILITY_ID)


## Free unless already planting — the job rule (MoveCommand.is_free_to_take).
static func is_free_to_take(actor: Actor) -> bool:
	return holds_none_of(actor, [Plant])


#endregion

#region Properties
## Ticks spent working in reach. Reset whenever the planter is out of reach, so being pushed
## away restarts the work rather than banking it.
var _worked: int = 0
#endregion


#region State updates
## Rigging a charge is a channeled action: a hit interrupts it as it interrupts building.
func blocked_by_stagger(_a_actor: Actor) -> bool:
	return true


## The order ends if the piece it named has gone, or the charge was spent meanwhile.
func get_updated_state(a_actor: Actor) -> Variant:
	if message.target != null and not is_instance_valid(message.target):
		return null
	if meets_precondition(a_actor, message) != PreconditionFailureCause.NONE:
		return null
	return self


func ends_on_arrival() -> bool:
	return false


func can_act(a_actor: Actor) -> bool:
	var carrier: Actor = _carrier_of(a_actor)
	var in_reach: bool
	if carrier != null and carrier.is_in_group("fixture"):
		in_reach = SU.unit_is_close_to_target(a_actor, carrier)
	else:
		in_reach = a_actor.xz_position.distance_to(message.xz_position) <= REACH
	if not in_reach:
		_worked = 0
	return in_reach


func fulfill_action(a_actor: Actor) -> Variant:
	_worked += 1
	if _worked < _required_ticks(a_actor):
		return self
	var pool := a_actor.get_node_or_null("Abilities") as Abilities
	if pool == null or not pool.spend(ABILITY_ID):
		return null
	_place_charge(a_actor)
	return null


#endregion


#region Private helpers
## The piece the charge will ride on, or null for a charge on the ground.
func _carrier_of(_a_actor: Actor) -> Actor:
	return message.target as Actor if PlantedCharge.can_carry(message.target) else null


func _required_ticks(a_actor: Actor) -> int:
	var carrier: Actor = _carrier_of(a_actor)
	if carrier == null or carrier.defense == null:
		return GROUND_CHANNEL_TICKS
	return maxi(1, ceili(TICKS_PER_TARGET_HP * carrier.defense.hp))


func _place_charge(a_actor: Actor) -> void:
	var map: Map = message.map if message.map != null else a_actor.map
	if map == null or a_actor.commander == null:
		return
	var piece := (load(CHARGE_SCENE_PATH) as PackedScene).instantiate() as Actor
	piece.initialize(map, a_actor.commander)
	var xz: Vector2 = message.xz_position
	piece.global_position = Vector3(xz.x, map.terrain_height_at(xz), xz.y)
	var charge: PlantedCharge = PlantedCharge.of(piece)
	if charge != null:
		charge.arm(a_actor, _carrier_of(a_actor))


#endregion


#region Debug
func _to_string() -> String:
	return "Plant: %s" % message.position
#endregion
