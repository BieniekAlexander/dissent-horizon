class_name Interact
extends Command

## Generalised interaction command. A unit carrying an [Interactor] component can
## Interact with any target whose `Entity.Type` matches one of the interactor's
## [Interaction]s. The unit moves into range, "interacts" for the interaction's
## `duration`, then the interaction's `event` scene is performed.
##
## Replaces the former per-type PickUp / DropOff / Lab-collect special cases:
## what a unit can interact with now lives entirely in its Interactor's list.

#region Properties
## Seconds spent interacting so far. Accumulates each tick the unit is in range
## (i.e. while can_act is true), and the interaction completes once it reaches
## the resolved Interaction's duration.
var _elapsed: float = 0.0
#endregion

#region Preconditions
static func requires_position() -> bool:
	return true

## Valid when the actor has an Interactor with an applicable interaction (per the
## interaction type's mapped precondition), and — if the target is aa Shelter —
## that Shelter is available (its startup countdown has elapsed).
static func meets_precondition(
	a_actor: Commandable,
	a_message: CommandMessage
) -> PreconditionFailureCause:
	if not is_instance_valid(a_message.target) or not (a_message.target is Entity):
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	if a_actor.interactor == null or not a_actor.interactor.can_interact(a_actor, a_message):
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	if not _target_available(a_message.target):
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	return PreconditionFailureCause.NONE
#endregion

#region Private helpers
## The interaction the actor would perform on the current target, or null.
func _interaction_for(a_actor: Commandable) -> Interaction:
	if a_actor.interactor == null:
		return null
	return a_actor.interactor.applicable_interaction(a_actor, message)

## True unless the target is aa Shelter still counting down. A target with no
## Shelter component is always considered available.
static func _target_available(target: Entity) -> bool:
	var shelter := target.get_node_or_null("Shelter") as Shelter
	return shelter == null or shelter.available

## Instantiate and perform the interaction's event scene.
##
## When the event's root is an Entity (e.g. a recruited unit), it is placed
## through Map.add_entity so it lands on the nearest navigable cell and is
## initialised under the actor's commander — dropping it at the target's
## position would spawn it inside the target structure.
##
## Any other scene is added to the active scene anchored at the target; a
## ScenarioEvent root additionally has execute() called and is then freed (a
## one-shot performance), while plain scenes are left to run their own _ready.
func _perform_event(a_actor: Commandable, interaction: Interaction) -> void:
	if interaction.event == null:
		return
	var instance: Node = interaction.event.instantiate()

	var anchor: Vector2 = VU.inXZ(a_actor.global_position)
	if is_instance_valid(message.target) and message.target is Node3D:
		anchor = VU.inXZ((message.target as Node3D).global_position)

	# A spawned Entity routes through the Map: add_entity snaps units to the
	# nearest navmesh point and assigns the commander. (Structures with an
	# Obstruction take the grid-placement path inside add_entities.)
	var map: Map = message.map if message.map != null else a_actor.map
	if instance is Entity and map != null:
		map.add_entity(instance as Entity, anchor, a_actor.commander)
		return

	var scene_root: Node = a_actor.get_tree().current_scene
	if scene_root == null:
		instance.queue_free()
		return
	scene_root.add_child(instance)
	if instance is Node3D and is_instance_valid(message.target):
		(instance as Node3D).global_position = (message.target as Node3D).global_position
	if instance.has_method("execute"):
		var manager := scene_root.find_child("ScenarioEventManager") as ScenarioEventManager
		instance.execute(manager)
		instance.queue_free()
#endregion

#region State updates
## Drop the command if the target vanished, the interaction no longer applies,
## or the target's Shelter went unavailable.
func get_updated_state(a_actor: Commandable) -> Command:
	if not is_instance_valid(message.target):
		return null
	if _interaction_for(a_actor) == null or not _target_available(message.target):
		return null
	return self

func should_move(a_actor: Commandable) -> bool:
	return is_instance_valid(message.target) \
		and not SU.unit_is_close_to_target(a_actor, message.target)

func can_act(a_actor: Commandable) -> bool:
	return is_instance_valid(message.target) \
		and SU.unit_is_close_to_target(a_actor, message.target)

## Accumulate interaction time while in range; perform the event once the
## interaction's duration has elapsed, then end the command.
func fulfill_action(a_actor: Commandable) -> Variant:
	var interaction := _interaction_for(a_actor)
	if interaction == null:
		return null
	_elapsed += a_actor.get_physics_process_delta_time()
	if _elapsed < interaction.duration:
		return self
	_perform_event(a_actor, interaction)
	_on_completed(interaction)
	return null

## Type-specific completion side effects. A completed LIBERATE consumes the
## target Shelter's availability, restarting its countdown to maximum so the
## shelter must recharge before it can be interacted with again.
func _on_completed(interaction: Interaction) -> void:
	if interaction.type != Interaction.Type.LIBERATE:
		return
	if not is_instance_valid(message.target):
		return
	var shelter := message.target.get_node_or_null("Shelter") as Shelter
	if shelter != null:
		shelter.reset()
#endregion

#region Debug
func _to_string() -> String:
	return "Interact: %s" % message.position
#endregion
