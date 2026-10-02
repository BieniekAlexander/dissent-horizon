@tool
class_name StunStatusEffect
extends StatusEffect

## Suppresses ALL command processing on the host — movement AND action alike — for
## `duration_ticks`. See Commandable.is_stunned() and the gate at the top of
## CommandReceiver._process_commands(). This is a harder stop than Commandable's
## built-in stagger (which only blocks a handful of opt-in actions like Build/Repair
## and never blocks movement); a stunned unit does nothing at all until it wears off.
##
## `affects_frames` restricts which hosts the stun actually takes hold on, as a
## Garrison-style bitmask over Defense.FrameType (reusing Garrison's own FRAME_*
## constants rather than redeclaring the frame/bit mapping). A host outside the mask
## is left alone: the effect removes itself immediately in _on_apply rather than
## sitting inert, so is_active() never lies about a target being stunned.

@export_flags("Bio:1", "Mech:2") var affects_frames: int = Garrison.FRAME_ANY


func _on_apply() -> void:
	var actor := _entity as Commandable
	if (
		actor == null
		or actor.defense == null
		or (Garrison.FRAME_BITS.get(actor.defense.frame_type, 0) & affects_frames) == 0
	):
		remove()
		return
	if actor.locomotion != null:
		actor.locomotion.stop()
