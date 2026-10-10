class_name Sortie
extends Node

## A called-in aircraft's tour over one point: in from off the map with its guns cold, ON
## STATION for a fixed time — circling the point, firing on what it finds and on Attack orders —
## then home the way it came, guns cold again, until it is off the board and removes itself.
## Rules: gdd/systems/macroeconomics/sanctions/off-map-abilities.md §Gunship.
##
## A COMPONENT, NOT A COMMAND, which is the difference from AirDropRun. The aircraft takes the
## player's Attack orders on station, and any order replaces the active one — so a run held as
## an order would be thrown away by the first target. The sortie sits beside the command queue
## instead: it flies the transit legs as [SortieLeg] orders, gates which orders the aircraft
## admits (Actor.update_commands), and keeps its weapons cold off station
## (Actor.can_use_weapons). Added at launch by EventGunship; no doc key, since only the
## gunship flies one.

enum Phase {
	## In from off the map to the station. Weapons cold.
	INBOUND,
	## Circling the station, weapons free, until the time on station runs out.
	ON_STATION,
	## Back out past the edge it came in over. Weapons cold.
	OUTBOUND,
}

## The node name the sortie is found by.
const NODE_NAME: String = "Sortie"

## How close to the station counts as over it, in world units. Generous for AirDropRun's
## reason: a fixed wing at cruise speed crosses a tight radius inside one physics tick.
const ARRIVAL_RADIUS: float = 2.0

var phase: Phase = Phase.INBOUND

## The point the aircraft circles on station.
var _station: Vector3 = Vector3.ZERO
## Where it came in from off the map, which is the way it goes home.
var _home: Vector3 = Vector3.ZERO
## Ticks left on station; counted down only while ON_STATION.
var _station_ticks_left: int = 0
var _map: Map = null


static func of(a_entity: Node) -> Sortie:
	return a_entity.get_node_or_null(NODE_NAME) as Sortie if a_entity != null else null


## Put [aircraft] on a sortie over [station], arriving from [home], for [station_seconds].
static func launch(
	aircraft: Actor, map: Map, home: Vector3, station: Vector3, station_seconds: float
) -> Sortie:
	var sortie := Sortie.new()
	sortie.name = NODE_NAME
	sortie._map = map
	sortie._home = home
	sortie._station = station
	sortie._station_ticks_left = TimeUtils.ticks_from_seconds(station_seconds)
	aircraft.add_child(sortie)
	sortie._fly_leg_to(station)
	return sortie


#region Queries
## Whether the aircraft is circling its station — the firing stage, between the two transits.
func is_on_station() -> bool:
	return phase == Phase.ON_STATION


## Whether the aircraft's weapons are live: on station and nowhere else.
func can_use_weapons() -> bool:
	return is_on_station()


## The orders out of [a_orders] the aircraft takes. In transit, only its own leg. On station,
## only orders that shoot from where it is — an Attack, a shot at the ground, a Stop — never
## one that sends it anywhere, since the station is the sanction's whole point.
func admit(a_orders: Array[MoveCommand]) -> Array[MoveCommand]:
	return a_orders.filter(func(order: MoveCommand) -> bool: return _admits(order))


func _admits(a_order: MoveCommand) -> bool:
	if a_order is SortieLeg:
		return true
	if phase != Phase.ON_STATION:
		return false
	return a_order is Attack or a_order is FocusFire or a_order is Stop


#endregion


#region Tick
## Framework-imposed per-tick state: the phase and the station clock.
func _physics_process(_a_delta: float) -> void:
	var aircraft := get_parent() as Actor
	if aircraft == null:
		return
	match phase:
		Phase.INBOUND:
			if aircraft.xz_position.distance_to(VU.in_xz(_station)) <= ARRIVAL_RADIUS:
				_take_station(aircraft)
			else:
				_hold_leg(aircraft, _station)
		Phase.ON_STATION:
			_station_ticks_left -= 1
			if _station_ticks_left <= 0:
				_leave(aircraft)
			elif aircraft.command_receiver.is_idle():
				_circle_station(aircraft)
		Phase.OUTBOUND:
			if OffMapArrival.has_left(_map, aircraft.xz_position):
				aircraft.queue_free()
			else:
				_hold_leg(aircraft, _outbound_point())


func _take_station(a_aircraft: Actor) -> void:
	phase = Phase.ON_STATION
	a_aircraft.update_commands(null)
	a_aircraft.locomotion.settle(_station)


## Idle on station circles the STATION, not wherever its last target died — a finished Attack
## leaves the orbit anchored on the target's last position (CommandReceiver._drop_command).
func _circle_station(a_aircraft: Actor) -> void:
	var aerial: Aerial = a_aircraft.aerial
	if aerial != null and not aerial.anchor().is_equal_approx(_station):
		a_aircraft.locomotion.settle(_station)


func _leave(a_aircraft: Actor) -> void:
	phase = Phase.OUTBOUND
	a_aircraft.update_commands(null)
	_fly_leg_to(_outbound_point())


## Out along the line it came in on, past its entry point and clear of the board whichever
## way that points (OffMapArrival.exit_xz).
func _outbound_point() -> Vector3:
	var home_xz: Vector2 = VU.in_xz(_home)
	var exit_xz: Vector2 = OffMapArrival.exit_xz(_map, home_xz, home_xz - VU.in_xz(_station))
	return Vector3(exit_xz.x, _home.y, exit_xz.y)


## Re-issue the transit leg if anything took it away — a Stop or a cleared queue is admitted as
## a null order, which no admission can refuse.
func _hold_leg(a_aircraft: Actor, a_destination: Vector3) -> void:
	if not (a_aircraft.current_command() is SortieLeg):
		_fly_leg_to(a_destination)


func _fly_leg_to(a_destination: Vector3) -> void:
	var aircraft := get_parent() as Actor
	aircraft.update_commands(SortieLeg.new(CommandMessage.new(_map, null, null, a_destination)))
#endregion
