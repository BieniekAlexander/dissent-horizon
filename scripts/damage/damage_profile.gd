class_name DamageProfile
extends Resource

## One row of the damage matrix (gdd/tasks.md "Damage System — Implementation
## Spec" §3): a damage type's multipliers against both defensive axes. Built at
## runtime by DamageCatalog.from_tsv() — resources/damage/damage_vs_{armour,frame}.tsv
## are the canonical, on-disk data (readable by the Python balance tooling too);
## this is only the in-memory shape DamageTable resolves against, never authored
## as a .tres. §5.3: rows are owned, never shared by reference — each profile
## built by from_tsv() is its own instance, even where two rows' numbers match.
##
## Keys off the pre-existing Damage.Type / Defense.FrameType / Defense.ArmourType
## enums rather than new ones — the spec's ELECTRICITY collided with this
## codebase's already-wired ELECTRIC, and the call (gdd/tasks.md, 2026-08-10) was
## to keep the name that already existed in code. Defense.FrameType itself was
## later renamed BIOLOGICAL/METALLIC -> BIO/MECH to match the gdd id convention
## (see gdd/id-rename-proposal.md), so this file's multipliers now match the
## spec's own axis names after all.

## §3.1: every multiplier in the matrix must be drawn from this set.
const MULTIPLIER_LADDER: PackedFloat32Array = [1.0, 0.75, 0.6, 0.4, 0.25, 0.15]

@export var id: Damage.Type

@export_group("Frame multipliers")
@export var bio_multiplier: float = 1.0
@export var mech_multiplier: float = 1.0

@export_group("Armour multipliers")
@export var light_multiplier: float = 1.0
@export var medium_multiplier: float = 1.0
@export var strong_multiplier: float = 1.0

func frame_multiplier(a_frame: Defense.FrameType) -> float:
	return bio_multiplier if a_frame == Defense.FrameType.BIO else mech_multiplier

func armour_multiplier(a_armour: Defense.ArmourType) -> float:
	match a_armour:
		Defense.ArmourType.LIGHT: return light_multiplier
		Defense.ArmourType.MEDIUM: return medium_multiplier
		Defense.ArmourType.STRONG: return strong_multiplier
		_: return 1.0
