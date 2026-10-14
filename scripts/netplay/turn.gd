class_name Turn
extends RefCounted

## One commander's orders for one tick: the unit of netplay. A turn is sent for EVERY tick,
## and an empty one is sent explicitly, because "this player gave no orders on tick N" has to be
## confirmed, not assumed. gdd/systems/commands/netplay.md §The model.
##
## Sealed by Lockstep, for every tick, from the orders given before it.

## The tick the turn's orders apply on.
var tick: int
## The commander whose player gave them.
var commander_id: int
## In the order they were given. Each order's own `tick` is set to this turn's.
var orders: Array[PlayerOrder] = []


func _init(a_tick: int = 0, a_commander_id: int = 0, a_orders: Array[PlayerOrder] = []) -> void:
	tick = a_tick
	commander_id = a_commander_id
	orders = a_orders.duplicate()
	for order: PlayerOrder in orders:
		order.tick = tick


func is_empty() -> bool:
	return orders.is_empty()


## The turn as one JSON-able dictionary; its orders in PlayerOrder.to_dict form, the encoding a
## replay file already uses.
func to_dict() -> Dictionary:
	var encoded: Array = []
	for order: PlayerOrder in orders:
		encoded.append(order.to_dict())
	return {"tick": tick, "commander": commander_id, "orders": encoded}


## The turn a dictionary from to_dict describes, or null when it is malformed or holds an order
## of another commander. JSON brings numbers back as floats.
static func from_dict(a_dict: Dictionary) -> Turn:
	if not a_dict.has("tick") or not a_dict.has("commander"):
		return null
	var commander: int = int(a_dict["commander"])
	var decoded: Array[PlayerOrder] = []
	for entry: Variant in a_dict.get("orders", []):
		if not entry is Dictionary:
			return null
		var order: PlayerOrder = PlayerOrder.from_dict(entry)
		if order == null or order.commander_id != commander:
			return null
		decoded.append(order)
	return Turn.new(int(a_dict["tick"]), commander, decoded)


## Whether `a_other` carries the same orders for the same slot and tick — how a resent turn is
## told from a contradicting one. Compared in wire form, so a turn decoded from JSON (whose
## numbers come back as floats) matches the turn it was encoded from.
func same_as(a_other: Turn) -> bool:
	return a_other != null and _canonical() == a_other._canonical()


func _canonical() -> String:
	var round_trip: Variant = JSON.parse_string(JSON.stringify(to_dict()))
	return JSON.stringify(round_trip)
