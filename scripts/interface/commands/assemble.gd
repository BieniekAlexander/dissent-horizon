class_name Assemble
extends MoveCommand

## Bring a structure that has already been PLACED to completion — the second half of a
## build order, and what every co-builder converges on.
##
## Build lays the foundation; Assemble is what the builder holds from that moment until
## `build_progress` reaches 1.0.
##
## SEPARATE FROM [Repair], which mends damaged things that are already FINISHED. One command
## cannot answer both, because "is this target workable?" has opposite answers for a
## half-built barracks and a dented tank — the split is at the precondition, and the
## channeled action below it is identical.
##
## Issued by Build (on placement, and on spotting a co-builder's structure — see
## Build.get_updated_state), and by a right-click from a Builds-capable unit onto a
## friendly structure of a type it can build that isn't finished yet.

#region Preconditions
static func meets_precondition(
	_actor: Commandable,
	_message: CommandMessage
) -> MoveCommand.PreconditionFailureCause:
	return PreconditionFailureCause.NONE
#endregion

#region Properties
## The actor that registered itself as a builder on the target structure. Stored so
## _notification(PREDELETE) can unregister it if the command is cancelled before completion.
var _builder: Commandable = null
#endregion

#region State updates
## Finishing construction is a channeled action: a hit staggers the worker,
## pausing build progress until the stagger wears off.
func blocked_by_stagger(_a_actor: Commandable) -> bool:
	return true

func get_updated_state(_a_actor: Commandable) -> Variant:
	# The structure being built can be destroyed mid-build. Once freed, message.target
	# reads as a previously-freed instance and any check on it (e.g.
	# unit_is_close_to_target's `is Entity`) crashes. Drop the command instead.
	if not is_instance_valid(message.target):
		return null
	return self

func acting_action(_a_actor: Commandable) -> ActionTracker.Action:
	return ActionTracker.Action.BUILDING

func can_act(a_actor: Commandable) -> bool:
	return SU.unit_is_close_to_target(a_actor, message.target)

## Assembling is not finished by arriving next to the structure — that is where the work
## STARTS. Ending on arrival would drop the command the moment the worker stopped moving,
## which is the same defect that used to lose a Build order on approach.
func ends_on_arrival() -> bool:
	return false

func fulfill_action(a_actor: Commandable) -> Variant:
	var site: Commandable = message.target
	if _builder == null:
		_builder = a_actor
		site.register_builder(a_actor)
	var just_built: bool = site.advance_build_progress(site.effective_build_increment())
	if just_built:
		# Construction just completed; re-evaluate the tech tree so any structure
		# gated on this one (e.g. Extractor requires Outpost) now unlocks.
		if site.commander != null:
			site.commander.proc_technology()
		if a_actor.veterancy != null:
			var spec: TechnologySpec = site.commander.technology_mapping.get(site.id) \
				if site.commander != null else null
			var xp: int = roundi(float(spec.energy_cost) * Veterancy.XP_PER_BUILD_ENERGY) if spec != null else 0
			a_actor.veterancy.gain_experience(xp)
			a_actor._fire_entity_occurrence(Entity.EntityOccurrence.ON_FINISH_BUILD)
		# If this actor landed to build (HOVERING builder in GROUNDED_TEMP), take off.
		if a_actor.aerial != null and a_actor.aerial.is_grounded_temp():
			a_actor.aerial.take_off()
	if site.build_progress >= 1.0:
		site.unregister_builder(a_actor)
		return null
	return self
#endregion

#region Lifecycle
func _init(a_message: CommandMessage) -> void:
	super(a_message)

func _notification(a_what: int) -> void:
	if a_what == NOTIFICATION_PREDELETE and is_instance_valid(_builder):
		# Validity-check BEFORE casting: the target can be destroyed mid-build, and in
		# Godot 4 `as` on an already-freed object throws ("Trying to cast a freed
		# object") — and a freed ref reads as `!= null` false, so is_instance_valid is
		# the only reliable guard. Nothing left to unregister if the target is gone.
		if message != null and is_instance_valid(message.target):
			var site: Commandable = message.target as Commandable
			if site != null:
				site.unregister_builder(_builder)
	super(a_what)
#endregion
