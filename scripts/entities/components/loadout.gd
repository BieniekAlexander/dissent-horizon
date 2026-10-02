class_name Loadout
extends Node3D

## Holds the Weapon nodes owned by a commandable. Each direct child that is a
## Weapon represents one weapon slot. Methods here are the single place that
## walks this list so callers don't do ad-hoc child iteration.


#region Public API
func get_weapons() -> Array:
	return get_children().filter(func(c: Node) -> bool: return c is Weapon)


func has_weapons() -> bool:
	for c in get_children():
		if c is Weapon:
			return true
	return false


## Returns the first Weapon child whose can_target() returns true for `target`,
## or null if none match.
func weapon_for_target(a_target: Entity) -> Weapon:
	for c in get_children():
		if c is Weapon and c.can_target(a_target):
			return c
	return null


func any_weapon_can_target(a_target: Entity) -> bool:
	return weapon_for_target(a_target) != null


## The first Weapon child that can be aimed at bare ground (see Weapon.can_fire_at_ground),
## or null. Asked per-actor by FocusFire; the same first-match rule weapon_for_target uses.
func weapon_for_ground_fire() -> Weapon:
	for c in get_children():
		if c is Weapon and (c as Weapon).can_fire_at_ground():
			return c
	return null


func can_fire_at_ground() -> bool:
	return weapon_for_ground_fire() != null


## Sum of each weapon's rough per-shot damage (see Weapon.per_shot_damage) — a
## coarse combat-power figure for AI estimates (e.g. Bot.estimate_army_strength).
## Not DPS: it doesn't factor fire rate (split_time_ticks/reload_time_ticks/clip_size); raise
## that to per-weapon DPS here if rate-of-fire ever needs to matter to the estimate.
func total_damage() -> float:
	var total := 0.0
	for w: Weapon in get_weapons():
		total += w.per_shot_damage()
	return total


#region Charged ammo
## Every CHARGED weapon this loadout holds (see Weapon.charged) — the ones that must be
## recharged from outside rather than reloading on a timer. Empty for the large majority
## of units, which is what makes the rearm checks below cheap to run every tick.
func charged_weapons() -> Array:
	return get_weapons().filter(func(w: Weapon) -> bool: return w.charged)


## True when this unit has any weapon that must be recharged externally. The capability
## question — "could this unit ever need an airfield?" — as opposed to whether it needs
## one right now.
func has_charged_weapons() -> bool:
	for c in get_children():
		if c is Weapon and (c as Weapon).charged:
			return true
	return false


## True when any charged weapon is below a full clip: there is something for a docking bay
## to do. This is the DOCKING test — a unit sent to rearm sits on the pad until every
## charged weapon is full, so a partial clip is still worth the trip.
func needs_recharge() -> bool:
	for c in get_children():
		if c is Weapon and (c as Weapon).needs_recharge():
			return true
	return false


## True when EVERY charged weapon is dry, and there is at least one. This is the
## AUTO-rearm test, and deliberately stricter than needs_recharge(): a unit that can still
## shoot something should stay in the fight and finish its order rather than breaking off
## to top up, so only a unit with nothing left to fire sends itself home.
func is_out_of_ammo() -> bool:
	var found: bool = false
	for c in get_children():
		if c is Weapon and (c as Weapon).charged:
			found = true
			if not (c as Weapon).is_out_of_ammo():
				return false
	return found


## Advance every charged weapon's recharge by `ticks`. Returns true once they are all
## full — the signal the docking sequence waits on before releasing the pad.
func recharge(a_ticks: float = 1.0) -> bool:
	var complete: bool = true
	for c in get_children():
		if c is Weapon and (c as Weapon).charged:
			complete = (c as Weapon).recharge(a_ticks) and complete
	return complete


## Rounds currently loaded across every charged weapon, and the rounds a full load would
## be. The pair the HUD's ammo pips count out — one pip per round of `charged_clip_size()`,
## the first `charged_ammo()` of them drawn solid (see StatusVisuals).
##
## SUMMED across weapons rather than reported per weapon: the player is being told how much
## this AIRCRAFT has left, and the rearm mechanic already treats the loadout as one thing
## (it flies home when every charged weapon is dry and sits on the pad until all are full).
func charged_ammo() -> int:
	var total: int = 0
	for c in get_children():
		if c is Weapon and (c as Weapon).charged:
			total += (c as Weapon).ammo()
	return total


func charged_clip_size() -> int:
	var total: int = 0
	for c in get_children():
		if c is Weapon and (c as Weapon).charged:
			total += (c as Weapon).clip_size
	return total


## The least-full charged weapon's fill fraction, 0.0–1.0 — what a HUD ammo bar should
## draw, since the unit is only fully rearmed when its emptiest weapon is. Returns 1.0
## when nothing here is charged, so a caller can render unconditionally.
func ammo_fraction() -> float:
	var lowest: float = 1.0
	for c in get_children():
		if c is Weapon and (c as Weapon).charged:
			lowest = minf(lowest, (c as Weapon).ammo_fraction())
	return lowest
#endregion
#endregion
