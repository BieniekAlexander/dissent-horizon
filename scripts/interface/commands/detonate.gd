class_name Detonate
extends MoveCommand

## Set a planted charge off. Given to the charge itself, or to the Sapper that planted it —
## which needs no sight of the charge to do it. gdd/systems/combat/planted-explosives.md.


#region Preconditions
static func requires_position() -> bool:
	return false


## Every selected piece that has a charge to set off does so: each one its own.
static func default_cast_arity(_message: CommandMessage) -> CastArity:
	return CastArity.ALL


## A live charge, or a planter with one in play.
static func meets_precondition(
	actor: Commandable, _message: CommandMessage
) -> MoveCommand.PreconditionFailureCause:
	return (
		PreconditionFailureCause.NONE
		if charge_of(actor) != null
		else PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	)


## The charge `a_actor` would set off: itself, or the one it planted. Null for neither.
static func charge_of(a_actor: Commandable) -> PlantedCharge:
	var own: PlantedCharge = PlantedCharge.of(a_actor)
	if own != null:
		return null if own.is_resolved() else own
	return PlantedCharge.planted_by(a_actor)


#endregion


#region State updates
func should_move(_a_actor: Commandable) -> bool:
	return false


func can_act(_a_actor: Commandable) -> bool:
	return true


func fulfill_action(a_actor: Commandable) -> Variant:
	var charge: PlantedCharge = charge_of(a_actor)
	if charge != null:
		charge.detonate()
	return null


#endregion


#region Debug
func _to_string() -> String:
	return "Detonate"
#endregion
