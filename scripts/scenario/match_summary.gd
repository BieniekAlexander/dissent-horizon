class_name MatchSummary
extends RefCounted

## Statistics derived from a match's event log (MatchLog.events, or a parsed file). Pure: an
## event array in, numbers out — the summary view reads these and nothing of the game.


## Commander ids as the match header lists them, in order; empty with no header.
static func commander_ids(events: Array) -> Array[int]:
	var out: Array[int] = []
	for event: Dictionary in events:
		if event.get("type") == MatchLog.MATCH_STARTED:
			for entry: Dictionary in event.get("commanders", []):
				out.append(int(entry["id"]))
			break
	return out


## The winner the log ended on, or -1 while the match is running or ended with none.
static func winner(events: Array) -> int:
	for i: int in range(events.size() - 1, -1, -1):
		if events[i].get("type") == MatchLog.MATCH_ENDED:
			return int(events[i]["winner"])
	return -1


## Every commander id that won — the winner's whole alliance in a team game — or empty while the
## match runs or when nobody won. A log written before alliances names only `winner`.
static func winners(events: Array) -> Array:
	for i: int in range(events.size() - 1, -1, -1):
		if events[i].get("type") == MatchLog.MATCH_ENDED:
			var named: Variant = events[i].get("winners")
			if named is Array:
				return (named as Array).map(func(id: Variant) -> int: return int(id))
			var one: int = int(events[i]["winner"])
			return [one] if one > 0 else []
	return []


## Per commander id: {"units": units trained, "structures": structures whose construction
## finished}. Every commander in the header appears, at zero if it made nothing. Pieces a match
## starts with, or takes by capture, were not made and are not counted.
static func created_counts(events: Array) -> Dictionary:
	var by_piece: Dictionary = created_by_piece(events)
	var counts: Dictionary = {}
	for id: int in by_piece:
		counts[id] = {
			"units": _total(by_piece[id]["units"]),
			"structures": _total(by_piece[id]["structures"]),
		}
	return counts


## The same counts broken down by piece. Per commander id: {"units": {piece id: count},
## "structures": {piece id: count}}, every commander in the header present.
static func created_by_piece(events: Array) -> Dictionary:
	var made: Dictionary = {}
	for id: int in commander_ids(events):
		made[id] = {"units": {}, "structures": {}}
	for event: Dictionary in events:
		var key: String = _created_key(event)
		if key == "":
			continue
		var id: int = int(event["commander"])
		if not made.has(id):
			made[id] = {"units": {}, "structures": {}}
		var pieces: Dictionary = made[id][key]
		pieces[event["piece"]] = pieces.get(event["piece"], 0) + 1
	return made


static func _total(counts: Dictionary) -> int:
	var total: int = 0
	for count: int in counts.values():
		total += count
	return total


## Which count `event` adds to, or "" for none.
static func _created_key(event: Dictionary) -> String:
	var type: Variant = event.get("type")
	if type == MatchLog.PURCHASE_COMPLETED and event.get("kind") == MatchLog.KIND_UNIT:
		return "units"
	if type == MatchLog.CONSTRUCTION_FINISHED:
		return "structures"
	return ""
