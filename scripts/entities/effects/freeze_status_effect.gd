@tool
class_name FreezeStatusEffect
extends StunStatusEffect

## Cryogenic freeze: the host is encased, so it can do NOTHING and is HARDER TO KILL
## while it stands there. Colonial Freeze 1 / Freeze 2 (see the sanction grid table in
## gdd/factions/colonial/colonial.md).
##
## Extends StunStatusEffect rather than reimplementing the stop, because the stop IS a
## stun — Commandable.is_stunned() looks for that class, and the gate at the top of
## CommandReceiver._process_commands() is what makes "no actions at all" true. Freeze
## adds one thing on top: while it is active the host's Defense.armour_type is raised
## one step, which is the "strengthening" half of the faction's cryogenics theme.
##
## ADMISSION IS BY ARMOUR, NOT BY FRAME, which is the whole reason _on_apply is
## overridden instead of inherited:
##   • STRONG armour cannot be frozen — there is no step above it to raise the host to,
##     so a heavy unit would take the immobilisation with none of the protection, and
##     the effect would read as a pure stun under a cryo name.
##   • STRUCTURES cannot be frozen. Freezing a building has no movement to stop, so it
##     would be a bare armour BUFF on a stationary target — the opposite of a debuff,
##     and trivially abusable on your own base.
## A refused host is left completely alone: the effect removes itself in _on_apply, as
## StunStatusEffect does for an out-of-mask frame, so is_active() never claims a unit is
## frozen when it is not.
##
## `affects_frames` is inherited but meaningless here (a freeze admits BIO and MECH
## alike), so it is hidden from the inspector rather than left as a knob that silently
## does nothing.

## 15 seconds at 30 physics ticks per second.
const DEFAULT_FREEZE_TICKS: int = 450

## How many armour steps the freeze adds. One, and STRONG is the ceiling — see above.
const ARMOUR_STEPS: int = 1


func _init() -> void:
	duration_ticks = DEFAULT_FREEZE_TICKS


func _validate_property(a_property: Dictionary) -> void:
	super(a_property)
	if a_property.name == "affects_frames":
		a_property.usage &= ~PROPERTY_USAGE_EDITOR


## True when `entity` is a legal freeze target: a non-structure Commandable whose armour
## has a step left above it. Static so the SANCTION can refuse a bad click before it
## spends its charge, asking exactly the question the effect will ask on apply.
static func can_freeze(entity: Entity) -> bool:
	var actor := entity as Commandable
	if actor == null or actor.defense == null:
		return false
	if actor.is_in_group("structure"):
		return false
	return actor.defense.armour_type < Defense.ArmourType.STRONG


## Whether the armour step was actually applied, so the thaw only ever gives back what
## the freeze took. Load-bearing for the REFUSAL path: remove() runs _on_remove
## unconditionally, so a freeze rejected in _on_apply would otherwise LOWER the armour of
## the very unit it declined to touch — turning "STRONG cannot be frozen" into a debuff.
var _armour_raised: bool = false


func _on_apply() -> void:
	if not can_freeze(_entity):
		remove()
		return
	var actor := _entity as Commandable
	actor.defense.armour_type = (
		(int(actor.defense.armour_type) + ARMOUR_STEPS) as Defense.ArmourType
	)
	_armour_raised = true
	if actor.locomotion != null:
		actor.locomotion.stop()


func _on_remove() -> void:
	if not _armour_raised:
		return
	_armour_raised = false
	# A host that died under the freeze has already been torn down; there is nothing left
	# to thaw and its Defense may be gone.
	var actor := _entity as Commandable
	if actor == null or not is_instance_valid(actor) or actor.defense == null:
		return
	actor.defense.armour_type = (
		(int(actor.defense.armour_type) - ARMOUR_STEPS) as Defense.ArmourType
	)
