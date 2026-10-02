@tool
class_name DockingBay
extends Node3D

## Docking bay component — the node-child that makes a structure an AIRFIELD: somewhere an
## aerial unit lands, parks, and recharges the weapons that cannot reload on their own
## (see Weapon.charged). Resolved by the node name "DockingBay", like every other optional
## component.
##
## Deliberately NOT a Garrison. A garrison holds its occupants as orphaned nodes — out of
## the tree, out of rendering, out of physics — which is exactly right for infantry inside
## a bunker and exactly wrong here: a parked aircraft must stay VISIBLE on its pad, remain
## selectable, and keep contributing its own vision. So the two mechanics share nothing
## but the word "capacity", and a structure could in principle carry both.
##
## Capacity is the number of DockingPad children (see docking_pad.gd), so it is authored
## by placing the parking spaces rather than by typing a number that could disagree with
## them.
##
## Pads are UNOWNED: any friendly aerial unit may claim any free pad at any of its
## commander's bays, holding it from the moment it begins its approach until it takes off
## again. The alternative — a pad belonging for life to the aircraft the airfield built,
## as in Command & Conquer: Generals — was considered and rejected: it makes the airfield
## a hard cap on the air force rather than a piece of infrastructure, and it strands a
## pad every time an aircraft dies far from home. What survives of that model is the SOFT
## GATE (see has_spare_capacity / Train.meets_precondition), which warns when a commander
## owns more aircraft than pads without refusing to build them.

#region Properties
## How fast this bay recharges a docked unit's weapons, as a multiplier on the rate
## Weapon.reload_time_ticks implies. 1.0 means a unit takes exactly its weapon's reload_time_ticks
## to
## refill; a faction whose airfields service faster raises it. Kept on the BAY rather than
## on the weapon because it describes the facility, not the gun — the same aircraft should
## turn around faster at a better airfield.
@export var charge_rate: float = 1.0

#endregion


#region Public API
## Every pad on this bay, in scene-tree order. That order is the authored one, so a bay
## fills front-to-back the way its artist laid the spaces out rather than arbitrarily.
func pads() -> Array[DockingPad]:
	var result: Array[DockingPad] = []
	for c: Node in get_children():
		if c is DockingPad:
			result.append(c as DockingPad)
	return result


## How many aircraft this bay can hold at once — the pad count, never a separate number.
func capacity() -> int:
	return pads().size()


## Pads with no live claimant.
func free_pads() -> Array[DockingPad]:
	return pads().filter(func(p: DockingPad) -> bool: return p.is_free())


func has_free_pad() -> bool:
	for p: DockingPad in pads():
		if p.is_free():
			return true
	return false


## The units currently holding a pad here — parked or inbound.
func claimants() -> Array[Commandable]:
	var result: Array[Commandable] = []
	for p: DockingPad in pads():
		var c: Commandable = p.claimed_by()
		if c != null:
			result.append(c)
	return result


## The pad `unit` already holds here, or null. Checked before reserving so a Rearm command
## re-entering its own approach reclaims its space rather than taking a second one.
func pad_held_by(a_unit: Commandable) -> DockingPad:
	for p: DockingPad in pads():
		if p.claimed_by() == a_unit:
			return p
	return null


## Whether this bay would take `unit` at all, ignoring how full it is. Three requirements,
## each doing distinct work:
##   * CAN DOCK — a runway is for aircraft, and for aircraft that use airfields. Asked of
##     Movement.can_dock(), which is the one statement of that rule: aerial locomotion
##     (the axis Garrison.occupiable_movements already uses, rather than a frame or armour
##     class) AND the airframe not having opted out via Movement.docks. The kamikaze drone
##     is the opt-out — expended on its first run, with no life to return to.
##   * SAME COMMANDER — unlike a garrison, which also admits neutral hosts, an airfield is
##     a service and services are not shared. Neutral (id 0) airfields are excluded too:
##     there is no one to service you.
##   * FINISHED — a half-built airfield has no deck to land on.
## Room is deliberately NOT part of this, mirroring Garrison.admits: a full bay still
## admits a unit, which then waits for a pad rather than being refused the order.
func admits(a_unit: Commandable) -> bool:
	if a_unit == null or not is_instance_valid(a_unit):
		return false
	if a_unit.docking == null:
		return false
	var host: Commandable = owner_commandable()
	if host == null or not host.is_built:
		return false
	if host.commander_id == 0 or host.commander_id != a_unit.commander_id:
		return false
	return true


## Both questions at once: may this unit dock here, and is there room right now. The
## admits / has_room / accepts trio mirrors Garrison's, so the two mechanics answer the
## same three questions under the same three names.
func accepts(a_unit: Commandable) -> bool:
	return admits(a_unit) and (has_free_pad() or pad_held_by(a_unit) != null)


## Claim a pad here for `unit`, returning it — or null when the bay is full. Idempotent:
## a unit that already holds a pad here gets the same one back, so a command re-reserving
## every tick cannot consume the whole bay.
func reserve(a_unit: Commandable) -> DockingPad:
	var held: DockingPad = pad_held_by(a_unit)
	if held != null:
		return held
	if not admits(a_unit):
		return null
	for p: DockingPad in pads():
		if p.is_free() and p.claim(a_unit):
			return p
	return null


## Drop whatever pad `unit` holds here. Safe to call for a unit that holds none.
func release(a_unit: Commandable) -> void:
	for p: DockingPad in pads():
		if p.claimed_by() == a_unit:
			p.release(a_unit)


## Recharge everything parked on this bay's pads by one tick's worth. Called from the
## STRUCTURE's per-tick update rather than from each docked unit's, so a unit that is
## parked and idle needs no special case of its own and the bay's charge_rate is applied
## in exactly one place.
##
## Only pads whose claimant has actually ARRIVED are charged — an inbound aircraft holds
## its pad from the moment it sets off, and rearming it in flight would let a unit refill
## without ever landing.
func tick_recharge() -> void:
	for p: DockingPad in pads():
		var unit: Commandable = p.claimed_by()
		if unit == null or unit.docking == null or not unit.docking.is_docked_at(p):
			continue
		if unit.weapon_inventory != null:
			unit.weapon_inventory.recharge(charge_rate)


## Every runway this airfield carries, in scene order. An airfield may have several; an
## aircraft uses the one nearest whichever pad it is assigned (see runway_for).
func runways() -> Array[Runway]:
	var out: Array[Runway] = []
	for c: Node in get_children():
		if c is Runway:
			out.append(c as Runway)
	return out


## The runway an aircraft on `a_pad` should use: the strip whose line passes closest to that
## pad, so the taxi out and the taxi back use the same one and the shortest.
##
## Null for a bay with no runway authored, which is the "descend straight onto the pad"
## fallback — what every airfield did before runways existed, and what a HOVERING dock
## would want in any case since a helicopter has no roll-out to fly.
func runway_for(a_pad: DockingPad) -> Runway:
	var best: Runway = null
	var best_distance: float = INF
	var from: Vector3 = a_pad.dock_position() if a_pad != null else global_position
	for strip: Runway in runways():
		var d: float = strip.distance_to(from)
		if d < best_distance:
			best_distance = d
			best = strip
	return best


## The Commandable this bay belongs to. Structures put their components directly under the
## entity root, so this is just the parent — resolved through a helper rather than inline
## so the one cast lives in one place.
func owner_commandable() -> Commandable:
	return get_parent() as Commandable
#endregion
