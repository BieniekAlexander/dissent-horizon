class_name Interaction
extends Resource

## A single interaction an [Interactor]-equipped unit can perform. The unit moves
## into range and "interacts" for `duration` seconds; on completion the interaction's
## effect runs (see [Interact] for the per-type completion logic).
##
## Applicability is decided by `type`: each Interaction.Type maps to an
## evaluation function (same signature as Command.meets_precondition) that
## inspects the actor/message and returns whether the interaction may proceed.
## Held in an [Interactor]'s `interactions` list.

#region Types
enum Type {
	## Liberate a Shelter: spawns the `event` units into the world under the actor's
	## commander, then resets the shelter. Applicable to any target with a Shelter.
	LIBERATE,
	## Abduct an enemy biological unit: on arrival the target is removed from the
	## game and stored in the actor's Inventory. Applicable to an enemy "infantry"
	## (biological-frame, non-structure) unit when the actor has free inventory space.
	ABDUCT,
	## Collect units from a ready Shelter into the actor's Inventory (rather than
	## spawning them into the world like LIBERATE). Puts up to `payload_count`
	## instances of `payload_scene` into the inventory, then resets the shelter.
	COLLECT,
	## Deposit the actor's carried units into the target's Inventory (e.g. an
	## internment camp). Applicable when the actor holds units and the target is a
	## structure with inventory space. Transfers as many as fit (partial allowed).
	DEPOSIT,
}
#endregion

#region Properties
## Which interaction this is; selects the evaluation function (see _evaluators).
@export var type: Interaction.Type = Interaction.Type.LIBERATE

## Scene performed when a LIBERATE interaction completes. A spawned Entity is placed
## via Map.add_entity (nearest navmesh point, under the actor's commander); other
## scenes are added to the active scene and, if a Event, executed. Unused by the
## inventory-based interaction types (ABDUCT/COLLECT/DEPOSIT).
@export var event: PackedScene

## For COLLECT: the unit scene instanced into the actor's Inventory on completion.
@export var payload_scene: PackedScene

## For COLLECT: how many `payload_scene` instances to produce (clamped to the actor's
## remaining inventory space).
@export var payload_count: int = 1

## Seconds the unit must remain interacting (in range) before completion.
@export var duration: float = 1.0

## How close (world units) the actor must get to a MOBILE target before it can act.
## 0 = the default near-touch contact. Matters for unit targets (e.g. ABDUCT): RVO
## avoidance keeps units apart, so a touch-only reach makes a carrier chase a mobile
## target forever — give capture a few units of reach so it can grab without colliding.
## Ignored for structure targets, which use footprint adjacency regardless.
@export var interact_range: float = 0.0
#endregion

#region Helpers
## The Inventory component on `target`, or null. The deposit target (e.g. an
## internment camp) receives carried units into this.
static func target_inventory(target: Node) -> Inventory:
	return target.get_node_or_null("Inventory") as Inventory if target != null else null
#endregion

#region Evaluation
## Per-type evaluation functions, each with the same signature as
## Command.meets_precondition: (a_actor, a_message) -> PreconditionFailureCause.
## Built lazily — static-var class-resolution order is fragile at init time.
static var _evaluators: Dictionary

static func _build_evaluators() -> Dictionary:
	return {
		Type.LIBERATE: func(_a_actor: Commandable, a_message: CommandMessage) -> Command.PreconditionFailureCause:
			return Command.PreconditionFailureCause.NONE \
				if is_instance_valid(a_message.target) and a_message.target.has_node("Shelter") \
				else Command.PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE,

		# Enemy "infantry" = a biological-frame, non-structure unit owned by an enemy.
		Type.ABDUCT: func(a_actor: Commandable, a_message: CommandMessage) -> Command.PreconditionFailureCause:
			return Command.PreconditionFailureCause.NONE \
				if is_instance_valid(a_message.target) and a_message.target is Entity \
					and a_actor.is_enemy_of(a_message.target) \
					and not a_message.target.has_node("Structure") \
					and EntityAttribute.evaluate(EntityAttribute.Type.IS_BIOLOGICAL, a_message.target) \
					and a_message.target.defense.armour_type == Defense.ArmourType.LIGHT \
					and a_actor.ability_inventory != null and a_actor.ability_inventory.can_hold_more() \
				else Command.PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE,

		Type.COLLECT: func(a_actor: Commandable, a_message: CommandMessage) -> Command.PreconditionFailureCause:
			return Command.PreconditionFailureCause.NONE \
				if is_instance_valid(a_message.target) and a_message.target.has_node("Shelter") \
					and a_actor.ability_inventory != null and a_actor.ability_inventory.can_hold_more() \
				else Command.PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE,

		# Deposit into any structure that has inventory space, when we carry units.
		Type.DEPOSIT: func(a_actor: Commandable, a_message: CommandMessage) -> Command.PreconditionFailureCause:
			return Command.PreconditionFailureCause.NONE \
				if is_instance_valid(a_message.target) and a_message.target.has_node("Structure") \
					and a_actor.ability_inventory != null and a_actor.ability_inventory.has_items() \
					and target_inventory(a_message.target) != null \
					and target_inventory(a_message.target).can_hold_more() \
				else Command.PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE,
	}

static func _evaluator_for(a_type: Interaction.Type) -> Callable:
	if _evaluators.is_empty():
		_evaluators = _build_evaluators()
	return _evaluators[a_type]

## Evaluate this interaction's applicability for the given actor/message, using
## the function mapped to its `type`.
func meets_precondition(
	a_actor: Commandable,
	a_message: CommandMessage
) -> Command.PreconditionFailureCause:
	return _evaluator_for(type).call(a_actor, a_message)
#endregion
