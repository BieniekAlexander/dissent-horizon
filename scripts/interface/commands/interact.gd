class_name Interact
extends MoveCommand

## Generalised interaction command. A unit carrying an [Interactor] component can
## Interact with any target whose `Entity.Type` matches one of the interactor's
## [Interaction]s. The unit moves into range, "interacts" for the interaction's
## `duration`, then the interaction's `event` scene is performed.
##
## Replaces the former per-type PickUp / DropOff / Lab-collect special cases:
## what a unit can interact with now lives entirely in its Interactor's list.

#region Properties
## Physics ticks spent interacting so far. Accumulates each tick the unit is in range
## (i.e. while can_act is true, so fulfill_action runs once per physics tick), and the
## interaction completes once it reaches the resolved Interaction's required_ticks.
var _elapsed_ticks: float = 0.0
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
## Any other scene is added to the active scene anchored at the target; an
## AbstractEvent root is run through ScenarioTriggerManager.run_event with the
## actor as the reaction source — so events using Assignment.INHERITED (e.g.
## liberation) assign their spawns to the liberating commander — then freed (a
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
	# Structure take the grid-placement path inside add_entities.)
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
	if instance is AbstractEvent:
		var manager := scene_root.find_child("ScenarioTriggerManager") as ScenarioTriggerManager
		if manager != null:
			# Run with the actor as reaction source so INHERITED-assignment events
			# spawn under the liberating commander; run_event also recurses nested events.
			manager.run_event(instance as AbstractEvent, a_actor)
		instance.queue_free()
#endregion

#region State updates
## Drop the command if the target vanished, the interaction no longer applies,
## or the target's Shelter went unavailable.
func get_updated_state(a_actor: Commandable) -> Variant:
	if not is_instance_valid(message.target):
		return null
	if _interaction_for(a_actor) == null or not _target_available(message.target):
		return null
	return self

func should_move(a_actor: Commandable) -> bool:
	return is_instance_valid(message.target) and not _in_reach(a_actor)

func can_act(a_actor: Commandable) -> bool:
	return is_instance_valid(message.target) and _in_reach(a_actor)

## Whether the actor is close enough to the target to perform the interaction.
## Structure targets always use footprint adjacency (scale-aware). For a MOBILE target,
## the resolved interaction's `interact_shape` (a collision volume centred on the actor)
## decides reach when set — letting an interaction (e.g. ABDUCT) grab a target a few
## units away without colliding — otherwise the default near-touch contact applies.
func _in_reach(a_actor: Commandable) -> bool:
	var target: Entity = message.target
	if target.is_in_group("structure"):
		return SU.unit_is_close_to_structure(a_actor, target)
	var interaction := _interaction_for(a_actor)
	if interaction != null and interaction.interact_shape != null:
		return SU.unit_shape_overlaps_target(a_actor, target, interaction.interact_shape)
	return SU.unit_is_close_to_target(a_actor, target)

## Accumulate interaction time while in range; perform the event once the
## interaction's duration has elapsed, then end the command.
func fulfill_action(a_actor: Commandable) -> Variant:
	var interaction := _interaction_for(a_actor)
	if interaction == null:
		return null
	_elapsed_ticks += 1.0
	if _elapsed_ticks < interaction.required_ticks(message.target):
		return self
	_complete(a_actor, interaction)
	return null

## Run the interaction's completion effect, dispatched by type. LIBERATE spawns the
## event units into the world; the inventory types (ABDUCT/COLLECT/DEPOSIT) move
## units between the actor's and target's Inventories instead.
func _complete(a_actor: Commandable, interaction: Interaction) -> void:
	match interaction.type:
		Interaction.Type.LIBERATE:
			_perform_event(a_actor, interaction)
			_reset_target_shelter()
		Interaction.Type.ABDUCT:
			_abduct(a_actor)
		Interaction.Type.COLLECT:
			_collect(a_actor, interaction)
			_reset_target_shelter()
		Interaction.Type.DEPOSIT:
			_deposit(a_actor)
		Interaction.Type.PLANT:
			_plant(a_actor, interaction)

## Remove the targeted enemy unit from the game and imprison it in the actor's
## Inventory. The captured instance is detached from the tree (so it leaves physics,
## fog, and group queries) but kept alive as the prisoner; the holder frees it on
## death (see Inventory). No-op if the actor's inventory filled up in the meantime.
func _abduct(a_actor: Commandable) -> void:
	if not is_instance_valid(message.target):
		return
	var inventory: Inventory = a_actor.ability_inventory
	if inventory == null or not inventory.can_hold_more():
		return
	var captive: Entity = message.target
	var parent: Node = captive.get_parent()
	if parent != null:
		parent.remove_child(captive)
	inventory.add_item(captive)

## Instantiate up to the interaction's payload_count units into the actor's
## Inventory (clamped to remaining space), without ever placing them in the world.
func _collect(a_actor: Commandable, interaction: Interaction) -> void:
	var inventory: Inventory = a_actor.ability_inventory
	if inventory == null or interaction.payload_scene == null:
		return
	for i: int in interaction.payload_count:
		if not inventory.can_hold_more():
			break
		inventory.add_item(interaction.payload_scene.instantiate() as Entity)

## Detonate a planted charge: spawn the interaction's projectile at the target's
## position, attributed to the planter's commander, and let it explode where it
## stands. Mirrors Weapon.fire's spawn sequence (initialize adds it to the tree and
## resolves ownership; initialize_projectile sets its origin/destination). No-op if
## the interaction has no projectile scene or the target vanished mid-plant.
func _plant(a_actor: Commandable, interaction: Interaction) -> void:
	if interaction.projectile_scene == null or not is_instance_valid(message.target):
		return
	var map: Map = message.map if message.map != null else a_actor.map
	if map == null:
		return
	var projectile: Projectile = interaction.projectile_scene.instantiate()
	projectile.initialize(map, a_actor.commander)
	projectile.global_position = (message.target as Node3D).global_position
	projectile.initialize_projectile(a_actor, message.target)

## Transfer carried units from the actor's Inventory into the target's, oldest first,
## until the target is full or the actor is empty (partial deposit allowed).
func _deposit(a_actor: Commandable) -> void:
	var source: Inventory = a_actor.ability_inventory
	var sink: Inventory = Interaction.target_inventory(message.target)
	if source == null or sink == null:
		return
	while source.has_items() and sink.can_hold_more():
		sink.add_item(source.items.pop_front())

## Restart the target Shelter's countdown so it must recharge before being used
## again. No-op when the target has no Shelter.
func _reset_target_shelter() -> void:
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
