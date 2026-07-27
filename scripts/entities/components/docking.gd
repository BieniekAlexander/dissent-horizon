class_name Docking
extends Node

## "Where is my dock?" — the unit-side half of an airfield (`DockingBay` / `DockingPad` are the
## structure side). Its presence is what makes a piece dock at all: the pad it stands on or has
## been handed, the runway it holds while rolling, leaving the dock, and taking itself home to
## rearm when its charged weapons run dry.
##
## TODO: every dock today is a deck an AIRCRAFT lands on, so "arrived at the dock" is asked of
## the piece's Aerial (Aerial.is_docked). A ground unit that docks needs its own arrival, and
## the importer refuses `docking:` without `aerial:` until one exists. See
## gdd/systems/authoring/composition-rework.md §Locomotion is bigger than `Movement`.

## The docking pad this piece is standing on, or null. Held from the moment it is put on the
## deck — rolled out by the airfield that built it, or parked at the end of a rearm — until it
## actually leaves, so the space cannot be handed to a second aircraft while one is sitting on
## it.
var docked_pad: DockingPad = null

## The runway this piece currently has to itself, or null. Held from the moment it starts
## rolling (or starts down the approach) until it is airborne or parked — see release_runway,
## which is the single place it goes back.
var claimed_runway: Runway = null


## `a_piece`'s Docking component, or null when it does not dock.
static func of(a_piece: Node) -> Docking:
	return a_piece.get_node_or_null("Docking") as Docking if a_piece != null else null


func host() -> Commandable:
	return get_parent() as Commandable


## True while the piece has arrived on a deck — parked, not merely grounded.
func is_on_deck() -> bool:
	var aerial: Aerial = Aerial.of(host())
	return aerial != null and aerial.is_docked()


## True while this piece is standing on a pad it holds. A HOVERING unit set down in a field by
## a Land command is grounded but holds no pad, and leaves by taking off in place.
func is_docked_on_pad() -> bool:
	return is_on_deck() and is_instance_valid(docked_pad)


## True when this piece is parked on `pad` — it holds that pad AND has actually finished
## its descent onto it. Both halves are needed: a pad is claimed from the moment its
## aircraft sets off, so holding one is not the same as standing on it, and an inbound
## aircraft that counted as docked would rearm itself in mid-air.
func is_docked_at(a_pad: DockingPad) -> bool:
	if a_pad == null or not is_instance_valid(a_pad) or a_pad.claimed_by() != host():
		return false
	return is_on_deck()


## Take this piece off its pad: give the space back and start the climb-out. The single exit
## from a parked state, called by CommandReceiver the moment anything wants to drive the
## piece somewhere. Safe to call on a piece that is not docked.
##
## This is what "it stays in its dock until something asks it to move" is made of — the
## aircraft is not waiting on a timer, it is waiting on an order.
func leave_dock() -> void:
	var aerial: Aerial = Aerial.of(host())
	if aerial == null:
		return
	var pad: DockingPad = docked_pad if is_instance_valid(docked_pad) else null
	var strip: Runway = _departure_runway(pad)
	if strip == null or not aerial.is_docked():
		# No runway authored (or nothing to roll off): straight up, which is what every airfield
		# did before runways existed and what a HOVERING dock would want anyway — a helicopter
		# lifts off the pad it is standing on.
		if pad != null:
			pad.release(host())
		docked_pad = null
		aerial.take_off()
		return
	# ONE AIRCRAFT PER STRIP. Somebody else is using it, so this one WAITS ON ITS PAD — it
	# keeps the space, nothing is released, and the caller tries again next tick. Rolling out
	# anyway would drive it through whatever is already down there.
	if not strip.claim(host()):
		return
	claimed_runway = strip
	if pad != null:
		pad.release(host())
	docked_pad = null
	# Join the strip at the nearest point to where it is parked, roll ALONG it to the
	# threshold, and only then climb. Two waypoints, because the first leg crosses the apron
	# and the second runs down the tarmac — going straight to the threshold would cut the
	# corner across the runway rather than entering it. Leg 1 is the TAKEOFF ROLL, so the
	# aircraft opens up toward flight speed along it rather than trundling to the threshold
	# and jumping into the air.
	var position: Vector3 = host().global_position
	aerial.taxi_along([strip.nearest_point(position), strip.takeoff_point()], aerial.take_off, 1)


## The airfield this piece was standing on has been destroyed under it.
##
## Why it works this way: gdd/systems/combat/aerial-operations/docking-bays-and-pads.md
## §Losing the deck under you.
func release_lost_dock() -> void:
	if not is_on_deck() or _holds_a_live_pad():
		return
	var piece: Commandable = host()
	var lost_dock_position: Vector3 = piece.global_position
	docked_pad = null
	if is_instance_valid(claimed_runway):
		claimed_runway.release(piece)
	claimed_runway = null
	var aerial: Aerial = Aerial.of(piece)
	aerial.take_off()
	var commander: Commander = piece.commander
	var bay: DockingBay = commander.nearest_docking_bay_for(piece) if commander != null else null
	var airfield: Commandable = bay.owner_commandable() if bay != null else null
	if airfield != null:
		# PREPENDED, like the automatic rearm: whatever the unit was going to do next is still
		# what it wants, it just has to find somewhere to stand first.
		piece.update_commands(Rearm.new(CommandMessage.new(
			piece.map, airfield, null, airfield.global_position)), true, true)
		return
	# Nowhere left to go: hold over the wreck rather than flying off, which is where the
	# player last saw it and where they will come looking.
	aerial.set_anchor(lost_dock_position)


## Give the runway back once this piece is done with it.
##
## Why it works this way: gdd/systems/combat/aerial-operations/runways.md §Releasing a runway
## is one place, both directions.
func release_runway() -> void:
	if claimed_runway == null:
		return
	if not is_instance_valid(claimed_runway):
		claimed_runway = null
		return
	# ON ITS PAD, not merely on the ground: `docked_pad` is handed over the moment the taxi
	# reaches the space (Rearm._park), which is exactly when the aircraft is done with the
	# strip. A bare is_on_deck() would release it on the single touchdown tick BEFORE the taxi
	# in starts, freeing the runway with an aircraft still rolling down it.
	var aerial: Aerial = Aerial.of(host())
	if aerial == null or aerial.is_airborne() or is_docked_on_pad():
		claimed_runway.release(host())
		claimed_runway = null


## While parked, swing the nose toward the taxiway. Costs nothing and is time the aircraft does
## not spend turning on the spot when an order finally arrives — on a pad facing away from the
## strip that turn was most of the delay before it moved.
func aim_parked_at_runway() -> void:
	# Whenever it is STANDING on a pad, not only when it is idle: an aircraft still taking on
	# fuel should already be pointing the way it will leave, so the turn is behind it by the
	# time the clip is full. Taxiing is excluded — is_on_deck() is false then — so this never
	# fights the taxi's own rotation.
	var piece: Commandable = host()
	if not is_on_deck() or docked_pad == null or not is_instance_valid(docked_pad) \
			or piece.movement == null:
		return
	var strip: Runway = _departure_runway(docked_pad)
	if strip == null:
		return
	var join: Vector3 = strip.nearest_point(piece.global_position)
	# Already on the join point (a pad sitting on the centreline): face down the strip
	# instead, which is where it goes next.
	if VU.inXZ(join).distance_to(VU.inXZ(piece.global_position)) < 0.05:
		join = strip.takeoff_point()
	piece.movement.face_toward(Vector3(join.x, piece.global_position.y, join.z))


## Send this piece to an airfield when its charged weapons run dry, and resume whatever it was
## doing once it is loaded again.
func maybe_auto_rearm() -> void:
	var piece: Commandable = host()
	if piece.weapon_inventory == null or not piece.weapon_inventory.is_out_of_ammo():
		return
	if piece.commander == null or piece.map == null:
		return
	for cmd: MoveCommand in piece.get_command_chain():
		if cmd is Rearm:
			return
	# ONLY IF IT HAS NOTHING ELSE WORTH DOING. It used to prepend a Rearm regardless, which
	# overrode a move order the player had just given — so an empty aircraft could not be
	# sent anywhere except back to its airfield. An order it cannot carry out unarmed has
	# already been stood down into the queue by Commandable._defer_unshootable_orders and does
	# not count as work; a plain move does, and is left alone.
	if not piece.command_receiver.awaiting_only_ammo_dependent_work():
		return
	# Already home: nothing to fly, and the bay is refilling it where it stands.
	if is_on_deck():
		return
	var bay: DockingBay = piece.commander.nearest_docking_bay_for(piece)
	if bay == null:
		return
	var airfield: Commandable = bay.owner_commandable()
	var msg := CommandMessage.new(piece.map, airfield, null, airfield.global_position)
	# PREPENDED, so it goes IN FRONT of whatever is waiting rather than replacing it. The
	# order this piece just stood down for lack of ammunition is sitting at the head of that
	# queue, and the whole point of standing it down rather than discarding it is that the
	# piece picks it up again the moment the rearm ends.
	piece.update_commands(Rearm.new(msg), true, true)


## The runway this piece should depart from: the strip nearest the pad it is leaving.
func _departure_runway(a_pad: DockingPad) -> Runway:
	if a_pad == null:
		return null
	var bay: DockingBay = a_pad.get_parent() as DockingBay
	return bay.runway_for(a_pad) if bay != null else null


## Whether some LIVE pad still holds this piece's claim — its own once handed over
## (`docked_pad`), or one a Rearm has reserved for it and not yet parked it on.
##
## The bay scan is what covers the second case, and it is why this asks the airfields
## rather than reading `docked_pad`: `docked_pad` is null for the whole descent and taxi,
## which is indistinguishable from "the deck I was standing on has been blown up" without
## it. Only ever walked while the piece is standing on a deck (see release_lost_dock), so
## it is a handful of pads on a handful of airfields, once per parked aircraft.
func _holds_a_live_pad() -> bool:
	if is_instance_valid(docked_pad):
		return true
	var commander: Commander = host().commander
	if commander == null:
		return false
	for bay: DockingBay in commander.docking_bays():
		if bay.pad_held_by(host()) != null:
			return true
	return false
