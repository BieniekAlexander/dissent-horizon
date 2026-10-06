@tool
class_name FreezeStatusEffect
extends StunStatusEffect

## Cryogenic freeze: the host is encased, so it can do NOTHING, and the ice is a CRYO Shield
## that takes damage before the host does. Breaking the shield breaks the freeze. Rules, and
## who applies it: gdd/systems/combat/shields.md §Freeze.
##
## Extends StunStatusEffect rather than reimplementing the stop, because the stop IS a stun —
## Commandable.is_stunned() looks for that class.
##
## REAPPLYING takes the larger of each: the remaining time and the shield's hit points (see
## _reapply_with). A frost field that holds a freeze on a unit standing in it extends only the
## time (hold_for), so the field does not mend the ice it is keeping up.
##
## `affects_frames` is inherited but meaningless here (a freeze admits BIO and MECH alike),
## so it is hidden from the inspector rather than left as a knob that silently does nothing.
## `duration_ticks` is hidden and never stored for the same kind of reason: every freeze lasts
## FREEZE_SECONDS, however it was applied.

## How long a freeze lasts. One constant for every applicator — the ordnance, the Avalanche and
## the Blizzard — decided 2026-10-05; a frost field may only hold one longer (hold_for).
const FREEZE_SECONDS: float = 10.0

## The ice's hit points.
@export var shield_hp: float = 150.0
## Whether the ice resists with its own armour class; false falls through to the host's.
@export var overrides_armour: bool = true
@export var shield_armour: Defense.ArmourType = Defense.ArmourType.STRONG
## Whether the ice resists as its own frame; false falls through to the host's.
@export var overrides_frame: bool = false
@export var shield_frame: Defense.FrameType = Defense.FrameType.MECH


func _init() -> void:
	duration_ticks = freeze_ticks()


## FREEZE_SECONDS in physics ticks, the unit a status effect counts in.
static func freeze_ticks() -> int:
	return TimeUtils.ticks_from_seconds(FREEZE_SECONDS)


func _validate_property(a_property: Dictionary) -> void:
	super(a_property)
	if a_property.name == "affects_frames":
		a_property.usage &= ~PROPERTY_USAGE_EDITOR
	elif a_property.name == "duration_ticks":
		a_property.usage &= ~(PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_STORAGE)


## True when `entity` may be frozen: a piece with a Defense, unit or structure, whose own
## armour is below STRONG. STRONG pieces are immune to cryogenics outright, which is also why
## an Avalanche never freezes itself in its own field. Static so a sanction can refuse a bad
## click before it spends its charge, asking exactly the question the effect asks on apply.
static func can_freeze(entity: Entity) -> bool:
	var actor := entity as Commandable
	if actor == null or actor.defense == null:
		return false
	return actor.defense.armour_type < Defense.ArmourType.STRONG


## Keep this freeze for at least `a_ticks` more, leaving the ice's hit points as they are.
func hold_for(a_ticks: int) -> void:
	var remaining: int = duration_ticks - _elapsed
	if a_ticks > remaining:
		duration_ticks = _elapsed + a_ticks


## The ice standing on the host, for the shield's hit points and their display.
func shield() -> Shield:
	var actor := _entity as Commandable
	if actor == null or not is_instance_valid(actor) or actor.defense == null:
		return null
	return actor.defense.shield_of(Shield.Type.CRYO)


func _on_apply() -> void:
	if not can_freeze(_entity):
		remove()
		return
	var actor := _entity as Commandable
	actor.defense.apply_shield(_new_shield())
	actor.defense.shield_broken.connect(_on_shield_broken)
	if actor.locomotion != null:
		actor.locomotion.stop()


## The larger of each, time and ice: a stronger freeze tops up a weaker one, and never the
## reverse. The incoming duplicate is discarded after this.
func _reapply_with(a_incoming: StatusEffect) -> void:
	source = a_incoming.source
	var incoming := a_incoming as FreezeStatusEffect
	if incoming == null:
		return
	hold_for(incoming.duration_ticks)
	var actor := _entity as Commandable
	if actor != null and actor.defense != null:
		actor.defense.apply_shield(incoming._new_shield())


func _on_remove() -> void:
	# A host that died under the freeze has already been torn down; there is nothing to thaw.
	var actor := _entity as Commandable
	if actor == null or not is_instance_valid(actor) or actor.defense == null:
		return
	if actor.defense.shield_broken.is_connected(_on_shield_broken):
		actor.defense.shield_broken.disconnect(_on_shield_broken)
	actor.defense.remove_shield(Shield.Type.CRYO)


func _on_shield_broken(a_type: Shield.Type) -> void:
	if a_type == Shield.Type.CRYO:
		remove()


func _new_shield() -> Shield:
	return Shield.new(
		Shield.Type.CRYO,
		shield_hp,
		shield_armour if overrides_armour else null,
		shield_frame if overrides_frame else null
	)
