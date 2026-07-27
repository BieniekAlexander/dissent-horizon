class_name CollisionLayers
extends RefCounted

## Pure constant holder — never instantiated: `CollisionLayers.Mask.*`,
## `CollisionLayers.TARGETABLE_ANY` and the side-bit helpers are read.
##
## MUST NOT extend an editor-only class (EditorScript, EditorPlugin, …): those types
## don't exist in export templates, so the script fails to parse in an exported build
## and every one of the ~50 gameplay scripts that names CollisionLayers fails to
## compile with it. The editor-side "write these names into ProjectSettings" tool
## lives in tools/apply_collision_layer_names.gd instead.

#region Constants
enum Mask {
	MOVEMENT_OBSTRUCTION = 1 << 0,  ## Units only. Governs physical push-back during move_and_slide.
	TARGETABLE_GROUND    = 1 << 1,  ## Ground units + all structures. Queried by aggro, vision, projectiles, AoE, and bot scans.
	TARGETABLE_AIR       = 1 << 2,  ## Aerial / hovering units. The anti-air counterpart of TARGETABLE_GROUND (kept adjacent to it).
	STRUCTURE_BLOCKER    = 1 << 3,  ## Finished obstructions only (Entity.blocks_line_of_fire). Queried by line-of-fire raycasts.
	STEALTH              = 1 << 4,  ## Set at runtime by Stealth component. Queried by detection-range checks.
	LIBERATABLE          = 1 << 5,  ## Set at runtime by Liberatable component. Queried by LiberationRange checks.
	TERRAIN              = 1 << 7,  ## Terrain StaticBody. Queried by ground-click raycasts.
	SELECTION            = 1 << 8,  ## Selectable Area3D. Queried by click-to-select raycasts.
}

## Both targetable layers OR'd together — the "find every attackable entity" mask
## for broad scans (aggro, vision, AoE, proximity, bot scans). Which of these layers
## a specific weapon may actually hit is filtered separately via Weapon.target_mask.
const TARGETABLE_ANY: int = Mask.TARGETABLE_GROUND | Mask.TARGETABLE_AIR

## Per-side copies of the two targetable layers, so an aggro query asks the physics engine for
## "hostile to me" instead of filtering allies out afterwards. A mask can only OR bits, so the
## layer has to encode the combination: a TargetBody keeps its generic TARGETABLE_* bit and also
## sets the one side bit for its layer and commander. Neutral (commander 0) has no side, which
## is what keeps it out of every hostile mask. Side slot k is commander id k + 1.
## See gdd/systems/combat/target-acquisition.md §Aggro filters allegiance in the physics query.
##
## Layers 10–17 (ground) and 18–25 (air): the free range above SELECTION.
const _GROUND_SIDE_FIRST_BIT: int = 9
const _AIR_SIDE_FIRST_BIT: int = _GROUND_SIDE_FIRST_BIT + Commander.NUM_MAX_COMMANDERS
## Every side bit on one targetable layer, before shifting into place.
const _ALL_SIDES: int = (1 << Commander.NUM_MAX_COMMANDERS) - 1
#endregion


## The side bits a body exposing the targetable `layers` (any mix of TARGETABLE_GROUND and
## TARGETABLE_AIR) carries for `commander_id`: one per layer, or 0 for neutral.
static func side_bits(layers: int, commander_id: int) -> int:
	if commander_id <= 0:
		return 0
	assert(commander_id <= Commander.NUM_MAX_COMMANDERS,
		"commander %d has no targetable side slot" % commander_id)
	var slot: int = commander_id - 1
	var out: int = 0
	if layers & Mask.TARGETABLE_GROUND:
		out |= 1 << (_GROUND_SIDE_FIRST_BIT + slot)
	if layers & Mask.TARGETABLE_AIR:
		out |= 1 << (_AIR_SIDE_FIRST_BIT + slot)
	return out


## Every side bit on the targetable `layers`: the mask of all owned, targetable bodies there.
static func all_side_bits(layers: int) -> int:
	var out: int = 0
	if layers & Mask.TARGETABLE_GROUND:
		out |= _ALL_SIDES << _GROUND_SIDE_FIRST_BIT
	if layers & Mask.TARGETABLE_AIR:
		out |= _ALL_SIDES << _AIR_SIDE_FIRST_BIT
	return out


## The query mask for bodies on the targetable `layers` that are hostile to `commander_id`
## (Entity.is_enemy_of): every side but its own, and never neutral.
static func hostile_mask(layers: int, commander_id: int) -> int:
	return all_side_bits(layers) & ~side_bits(layers, commander_id)

