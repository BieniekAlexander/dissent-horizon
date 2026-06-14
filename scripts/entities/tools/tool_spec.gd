class_name ToolSpec

## One ability "slot" owned by an entity (held in its Inventory component). A
## ToolSpec names which Ability.Type it grants and tracks the charge/reload
## bookkeeping for using it: charges are spent on use and regenerate over time
## up to max_charges, one charge per reload period.

#region Constants
const DEFAULT_MAX_CHARGES: int = 3
## Reload period, in physics frames, to restore one charge (90 ≈ 3s at 30 tps).
const DEFAULT_RELOAD_FRAMES: int = 90
#endregion

#region Properties
var ability_type: Ability.Type
var max_charges: int
var current_charges: int
## Frames remaining until the next charge is restored. Only counts down while
## current_charges < max_charges.
var reload_timer: int
#endregion

#region Lifecycle
func _init(
	a_ability_type: Ability.Type,
	a_max_charges: int = DEFAULT_MAX_CHARGES,
	a_current_charges: int = DEFAULT_MAX_CHARGES,
	a_reload_timer: int = DEFAULT_RELOAD_FRAMES
) -> void:
	ability_type = a_ability_type
	max_charges = a_max_charges
	current_charges = a_current_charges
	reload_timer = a_reload_timer
#endregion

#region Public API
func has_charge() -> bool:
	return current_charges > 0

## Spend one charge. Returns false (without spending) if none are available.
func consume() -> bool:
	if current_charges <= 0:
		return false
	current_charges -= 1
	return true

## Advance the reload by one physics frame, restoring a charge when the timer
## elapses (only while below max). Call once per physics tick.
func tick() -> void:
	if current_charges >= max_charges:
		reload_timer = DEFAULT_RELOAD_FRAMES
		return
	reload_timer -= 1
	if reload_timer <= 0:
		current_charges += 1
		reload_timer = DEFAULT_RELOAD_FRAMES
#endregion
