class_name TurnPacket
extends RefCounted

## What one peer sends another: the sender's turns the receiver has not acknowledged yet, and
## the sender's acknowledgement of the receiver's. Every packet repeats every unacknowledged turn,
## so a lost packet costs nothing but the wait for the next one: no retransmission timers, and
## an unreliable channel is enough. gdd/systems/commands/netplay.md §What lockstep builds that
## rollback keeps (the wire format).
##
## Encoded as JSON, its turns in the PlayerOrder.to_dict form a replay file already uses.
##
## Sent by Lockstep.pump, every frame, to every peer.

## Bumped on any change to the encoding; a packet of another version is refused, never guessed at.
const WIRE_VERSION: int = 2

## The commander whose turns these are.
var sender_id: int
## The newest tick up to which every one of the RECEIVER's turns has reached the sender;
## the receiver stops resending those.
var ack: int
var turns: Array[Turn] = []
## The sender's votes to drop a silent peer (Lockstep.vote_out), each {"commander": id, "newest":
## the newest tick up to which the sender holds its turns, "turns": those turns, relayed so every
## voter ends up holding the same ones}.
var drops: Array = []


func _init(
	a_sender_id: int = 0, a_ack: int = -1, a_turns: Array[Turn] = [], a_drops: Array = []
) -> void:
	drops = a_drops
	sender_id = a_sender_id
	ack = a_ack
	turns = a_turns.duplicate()


func encode() -> PackedByteArray:
	var encoded: Array = []
	for t: Turn in turns:
		encoded.append(t.to_dict())
	var body: Dictionary = {"v": WIRE_VERSION, "from": sender_id, "ack": ack, "turns": encoded}
	if not drops.is_empty():
		var votes: Array = []
		for vote: Dictionary in drops:
			var relayed: Array = (vote["turns"] as Array).map(
				func(t: Turn) -> Dictionary: return t.to_dict()
			)
			votes.append(
				{"commander": vote["commander"], "newest": vote["newest"], "turns": relayed}
			)
		body["drops"] = votes
	return JSON.stringify(body).to_utf8_buffer()


## The packet `a_bytes` encodes, or null when it is not one: unparseable, another wire version,
## or holding a turn that is malformed or not the sender's own.
static func decode(a_bytes: PackedByteArray) -> TurnPacket:
	# An instance's parse() reports a malformed packet by its return value; JSON.parse_string
	# would also log an engine error for what is only a bad packet from the network.
	var json := JSON.new()
	if json.parse(a_bytes.get_string_from_utf8()) != OK or not json.data is Dictionary:
		return null
	var body: Dictionary = json.data
	if int(body.get("v", -1)) != WIRE_VERSION or not body.has("from") or not body.has("ack"):
		return null
	var sender: int = int(body["from"])
	var decoded: Array[Turn] = []
	var raw_turns: Variant = body.get("turns", [])
	if not raw_turns is Array:
		return null
	for entry: Variant in raw_turns:
		if not entry is Dictionary:
			return null
		var t: Turn = Turn.from_dict(entry)
		if t == null or t.commander_id != sender:
			return null
		decoded.append(t)
	var votes: Array = []
	var raw_drops: Variant = body.get("drops", [])
	if not raw_drops is Array:
		return null
	for raw: Variant in raw_drops:
		if not raw is Dictionary or not (raw as Dictionary).has("commander"):
			return null
		var dropped: int = int(raw["commander"])
		var relayed: Array[Turn] = []
		for entry: Variant in raw.get("turns", []):
			var t: Turn = Turn.from_dict(entry) if entry is Dictionary else null
			if t == null or t.commander_id != dropped:
				return null
			relayed.append(t)
		votes.append({"commander": dropped, "newest": int(raw.get("newest", -1)), "turns": relayed})
	return TurnPacket.new(sender, int(body["ack"]), decoded, votes)
