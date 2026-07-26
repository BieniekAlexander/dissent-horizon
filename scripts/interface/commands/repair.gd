class_name Repair
extends MoveCommand

#region Preconditions
static func meets_precondition(
	a_actor: Commandable,
	a_message: CommandMessage
) -> MoveCommand.PreconditionFailureCause:
	return PreconditionFailureCause.NONE
#endregion

#region Properties
## The actor that registered itself as a builder on the target structure. Stored so
## _notification(PREDELETE) can unregister it if the command is cancelled before completion.
var _builder: Commandable = null
#endregion

#region State updates
## Repairing/finishing construction is a channeled action: a hit staggers the worker,
## pausing build progress until the stagger wears off.
func blocked_by_stagger(_a_actor: Commandable) -> bool:
	return true

func get_updated_state(a_actor: Commandable) -> Variant:
	# The repair target (the structure being built/repaired) can be destroyed mid-build.
	# Once freed, message.target reads as a previously-freed instance and any check on it
	# (e.g. unit_is_close_to_target's `is Entity`) crashes. Drop the command instead.
	if not is_instance_valid(message.target):
		return null
	return self

func can_act(a_actor: Commandable) -> bool:
	return SU.unit_is_close_to_target(a_actor, message.target)

func fulfill_action(a_actor: Commandable) -> Variant:
	var repairable: Commandable = message.target
	if _builder == null:
		_builder = a_actor
		repairable.register_builder(a_actor)
	var just_built: bool = repairable.advance_build_progress(repairable.effective_build_increment())
	if just_built:
		# Construction just completed; re-evaluate the tech tree so any structure
		# gated on this one (e.g. Mine requires Outpost) now unlocks.
		if repairable.commander != null:
			repairable.commander.proc_technology()
		if a_actor.veterancy != null:
			var spec: TechnologySpec = repairable.commander.technology_mapping.get(repairable.id) \
				if repairable.commander != null else null
			var xp: int = roundi(float(spec.ore_cost) * Veterancy.XP_PER_BUILD_ORE) if spec != null else 0
			a_actor.veterancy.gain_experience(xp)
			a_actor._fire_entity_occurrence(Entity.EntityOccurrence.ON_FINISH_BUILD)
		# If this actor landed to build (HOVERING builder in GROUNDED_TEMP), take off.
		if a_actor.movement != null and a_actor.movement.is_grounded_temp():
			a_actor.movement.take_off()
	if repairable.build_progress >= 1.0:
		repairable.unregister_builder(a_actor)
		return null
	return self
#endregion

#region Lifecycle
func _init(a_message: CommandMessage) -> void:
	super(a_message)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_builder):
		# Validity-check BEFORE casting: the target can be destroyed mid-build, and in
		# Godot 4 `as` on an already-freed object throws ("Trying to cast a freed
		# object") — and a freed ref reads as `!= null` false, so is_instance_valid is
		# the only reliable guard. Nothing left to unregister if the target is gone.
		if message != null and is_instance_valid(message.target):
			var repairable: Commandable = message.target as Commandable
			if repairable != null:
				repairable.unregister_builder(_builder)
	super(what)
#endregion
