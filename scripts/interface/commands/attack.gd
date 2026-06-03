class_name Attack
extends Command


## COMMAND PRECONDITIONS
static func requires_position() -> bool:
	return true

static func meets_precondition(
	a_actor: Commandable,
	a_message: CommandMessage
) -> PreconditionFailureCause:
	if not _target_attackable(a_message):
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	if a_actor == null or a_actor.weapon_inventory == null \
			or not a_actor.weapon_inventory.any_weapon_can_target(a_message.target):
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	return PreconditionFailureCause.NONE


### UTILS
static func _target_attackable(a_message: CommandMessage) -> bool:
	# TODO make it possible for units to attack the floor - unfortunately,
	# I previously wrote this such that a_message.target==null => the floor should be attacked,
	# but a_message.target becomes nul when a target dies, so checking it in that manner
	# causes this to always return true, even if the target used to be an object,
	# causing downstream checks to crash
	return is_instance_valid(a_message.target)

## Returns true when a structure's physics body lies on the line between
## a_actor and a_target (excluding a_target itself, so attacking a structure
## directly is never blocked by that same structure).
static func _structure_on_line(a_actor: Commandable, a_target: Entity) -> bool:
	var space_state := a_actor.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		a_actor.global_position,
		a_target.global_position,
		CollisionLayers.Layer.STRUCTURE_BLOCKER
	)
	query.exclude = [a_target.get_rid()]
	return not space_state.intersect_ray(query).is_empty()

## Returns the weapon from a_actor's inventory that can target message.target,
## or null if none can.
func _weapon_for(a_actor: Commandable) -> Weapon:
	if a_actor.weapon_inventory == null:
		return null
	return a_actor.weapon_inventory.weapon_for_target(message.target)


### STATE UPDATES
func get_updated_state(a_actor: Commandable):
	## Potentially return a new command based on a state check
	return null if not is_instance_valid(message.target) else self

func should_move(a_actor: Commandable) -> bool:
	if not _target_attackable(message):
		return false
	var weapon := _weapon_for(a_actor)
	if weapon == null:
		return false
	return (
		not SU.is_in_attack_range(weapon, a_actor, message.target)
		or _structure_on_line(a_actor, message.target)
	)

func can_act(a_actor: Commandable) -> bool:
	if a_actor.attack_timer > 0 or not _target_attackable(message) or message.target == a_actor:
		return false
	var weapon := _weapon_for(a_actor)
	return (
		weapon != null
		and SU.is_in_attack_range(weapon, a_actor, message.target)
		and not _structure_on_line(a_actor, message.target)
	)

func fulfill_action(a_actor: Commandable) -> Variant:
	var weapon := _weapon_for(a_actor)
	a_actor.attack_timer = weapon.attack_duration
	a_actor._attack_duration = weapon.attack_duration
	weapon.fire(a_actor, message.target)
	# Attacking breaks stealth: force the timed UNSTEALTHED window.
	if a_actor.stealth != null:
		a_actor.stealth.unstealth()
	return self

## DEBUG
func _to_string() -> String:
	return "Attack: %s" % message.position
