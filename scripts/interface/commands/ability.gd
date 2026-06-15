class_name Ability
extends Command

## Generic position-targeted ability command (repurposed from the old Launch).
##
## Which ability is being used is carried on message.ability_type. The payload
## to spawn (a Projectile scene) is resolved per-commander from
## Commander.ability_payload_registry, while availability/prerequisites/cost are
## gated through Commander.technology_mapping (get_unmet_need). Whether the
## actor even *has* the ability is decided by its Inventory: it must hold a
## ToolSpec for message.ability_type, and that ToolSpec must have a charge left.

#region Constants
enum Type {
	RADIATION,
}

## Max XZ distance from the target position at which the ability can be used.
const RANGE: float = 5.0
#endregion

#region Preconditions
static func meets_precondition(a_actor: Commandable, a_message: CommandMessage) -> PreconditionFailureCause:
	if a_actor == null or a_message.ability_type == null:
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	var spec := _tool_spec_for(a_actor, a_message.ability_type)
	# No ToolSpec for this ability → the unit simply doesn't have it.
	if spec == null:
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	# Out of charges (still reloading).
	if not spec.has_charge():
		return PreconditionFailureCause.ABILITY_NO_CHARGES
	# Availability / prerequisites / cost live in the commander's tech registry.
	var unmet: TechnologySpec.UnmetNeed = a_actor.commander.get_unmet_need(a_message.ability_type)
	if unmet != TechnologySpec.UnmetNeed.NONE:
		return unmet_need_to_precondition[unmet]
	return PreconditionFailureCause.NONE
#endregion

#region Private helpers
static func _tool_spec_for(a_actor: Commandable, a_ability_type: Variant) -> ToolSpec:
	if a_actor == null:
		return null
	var inventory := a_actor.get_node_or_null("Inventory") as Inventory
	if inventory == null:
		return null
	return inventory.tool_spec_for(a_ability_type)
#endregion

#region State updates
func should_move(a_actor: Commandable) -> bool:
	return not can_act(a_actor)

func can_act(a_actor: Commandable) -> bool:
	return (a_actor.xz_position - message.xz_position).length_squared() < Ability.RANGE * Ability.RANGE

func fulfill_action(a_actor: Commandable) -> Variant:
	var spec := _tool_spec_for(a_actor, message.ability_type)
	if spec == null or not spec.consume():
		return null

	var scene: PackedScene = a_actor.commander.ability_payload_registry.get(message.ability_type)
	if scene == null:
		push_error("no ability payload registered for ability_type %s" % message.ability_type)
		return null

	# All ability payloads are Projectiles: add them directly via initialize()
	# (not map.add_entity, which runs unit-placement spreading logic and expects
	# a MOVEMENT_OBSTRUCTION collision shape that projectiles don't have).
	var projectile: Projectile = scene.instantiate()
	projectile.initialize(message.map, a_actor.commander)
	projectile.global_position = a_actor.global_position
	projectile.initialize_projectile(a_actor, message.position)
	return null
#endregion
