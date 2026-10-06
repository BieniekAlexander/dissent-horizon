@tool
class_name EventTargetUnit extends AbstractEvent

## Base class for sanction events that act on ONE unit — Promotion, Freeze, Dignify,
## Informant, Overcharge, and any later ability of that kind. The unit is NAMED by the order:
## the player points at it (RTSController picks the unit under the cursor that this event
## accepts) and the activating Sanction hands it over as `target_unit`. There is no area and
## no search around the aim point — "the nearest qualifying unit within a radius" is what this
## used to do, and it is why the armed cursor drew a circle that described nothing the player
## could see.
##
## Two knobs, and they are deliberately separate questions:
##   • `scope` — WHOSE units may be picked. Most of these sanctions buff your own army
##     (Promote, Informant), but some act on anyone (Colonial Freeze 2, Anarchical
##     Overcharge), and a subclass should not have to reimplement an ownership test to
##     say so. Authored per SANCTION SCENE, which is what lets one script serve Freeze 1
##     (own) and Freeze 2 (any) with no second subclass.
##   • `_qualifies()` — WHAT else the unit must be. Overridden by subclasses for the
##     conditions only they know about (already stunned, not yet promoted, of one piece id).
##
## `accepts` is the one statement of both, asked by the cursor (which unit is highlighted),
## by UseSanction (whether the order may be given at all) and here (whether the unit named
## is still a legal target when the cast lands). A cast with no accepted unit is refused
## BEFORE a charge is spent — see Sanction.activate.

## Whose units may be picked.
enum Scope {
	OWN = 0,  ## only the activating commander's own units
	ANY = 1,  ## anyone's — friendly, hostile or neutral
}

@export var scope: Scope = Scope.OWN

## Commander whose sanction this is. Set by the activating Sanction before execute, so
## the same event serves the human player and any bot. Under Scope.OWN it is also the
## ownership filter; under Scope.ANY it only decides who gets the credit.
var commander_id: int = 1

## The unit this cast acts on, handed over by the activating Sanction. Null means no unit
## was named, and the event does nothing.
var target_unit: Commandable = null


## Extra per-subclass admission test, asked after scope. Default: anything.
func _qualifies(_a_candidate: Commandable) -> bool:
	return true


## Whether this event may name a structure as well as a unit. Default: units only.
func _admits_structures() -> bool:
	return false


## Whether `a_candidate` is a piece this event may act on for `a_commander_id`: a live unit
## (or structure, where `_admits_structures` allows), inside `scope`, and passing
## `_qualifies`. Untyped parameter, because the cursor and a queued order can both hand over
## something freed since it was named.
func accepts(a_candidate: Variant, a_commander_id: int) -> bool:
	if not is_instance_valid(a_candidate) or not (a_candidate is Commandable):
		return false
	var unit: Commandable = a_candidate
	if unit.is_queued_for_deletion():
		return false
	var is_structure: bool = unit.is_in_group("structure")
	if not (unit.is_in_group("unit") or (is_structure and _admits_structures())):
		return false
	if scope == Scope.OWN and unit.commander_id != a_commander_id:
		return false
	return _qualifies(unit)


## The named target, if it is still one this event accepts; otherwise null.
func _find_target_unit(_a_manager: ScenarioTriggerManager) -> Commandable:
	return target_unit if accepts(target_unit, commander_id) else null
