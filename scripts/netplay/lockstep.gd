class_name Lockstep
extends RefCounted

## One machine's side of a networked match: seals the local player's orders into a turn for the
## tick they will apply on (the tick they were given plus the input delay), exchanges turns with
## every peer, and says whether a tick may run — only once every peer's turn for it is in.
## gdd/systems/commands/netplay.md §The model.
##
## The stream drives it once per physics frame, stalled or not: seal(tick), then pump(), then
## can_run(tick) and take(tick). It never touches the simulation itself, so it is tested over a
## LoopbackNetwork with no scenario at all.
##
## Every peer applies the DECODED form of every turn, its own included: a local turn is sealed
## through the same JSON round trip a remote one arrives through, so a value the wire would round
## (a float) cannot read differently on the machine that gave the order.
##
## Made by NetMatch when the match starts. PLANNED: the Multiplayer lobby that builds a NetMatch
## (netplay.md §Decisions, entry).

## How many ticks past the newest confirmed one a tick may run. Zero, because nothing can correct
## a tick run on a guess until rollback exists; rollback is this same loop with it raised.
const RUN_AHEAD_TICKS: int = 0

## Ticks between a local order being given and applying, on every peer.
var input_delay_ticks: int
## The commander the local player commands.
var local_commander_id: int

var _buffer: InputBuffer
var _transport: NetTransport
## Transport peer id -> the commander that peer commands. A packet is believed only from the peer
## whose commander it claims to be.
var _commander_of_peer: Dictionary = {}
## Orders given since the last sealed turn, oldest first.
var _pending: Array[PlayerOrder] = []
## Local turns some peer has not acknowledged yet, oldest first; every packet repeats them.
var _unacknowledged: Array[Turn] = []
## Remote commander id -> the newest tick up to which it holds every local turn.
var _acknowledged: Dictionary = {}
## The newest tick a local turn has been sealed for.
var _sealed_through: int
## The first tick a peer sent two different turns for, and that peer; -1 while none has. Every
## peer may then believe a different turn, so NetMatch ends the match as a desync.
var contradiction_tick: int = -1
var contradiction_commander: int = -1

## Dropping a silent peer (netplay.md §Decisions, a silent peer). A peer that has waited too long
## on another VOTES it out (vote_out) and from then on ignores its packets, so its vote — how far
## it holds the silent peer's turns — never changes; every vote carries those turns too. Once every
## peer still playing has voted, each fences the silent peer one tick past the furthest any vote
## reached: every remaining peer reaches that same tick, holding the same turns before it.
## Commander -> {voter commander -> the newest tick the voter held its turns up to}.
var _votes: Dictionary = {}
## Commander -> this machine's vote on it: the commanders this machine has voted out.
var _voted_out: Dictionary = {}
## Commander -> the tick it forfeits on, once fenced.
var _fenced_at: Dictionary = {}


## A session starting on `a_first_tick`, its delay given in seconds, the unit the lobby measures
## a round trip in. Seals the local player's empty turns for the ticks no order can reach yet,
## since nothing given before the match could land on them.
func _init(
	a_transport: NetTransport,
	a_local_commander_id: int,
	a_commander_of_peer: Dictionary,
	a_input_delay_seconds: float,
	a_first_tick: int = 0
) -> void:
	_transport = a_transport
	local_commander_id = a_local_commander_id
	_commander_of_peer = a_commander_of_peer.duplicate()
	input_delay_ticks = maxi(TimeUtils.ticks_from_seconds(a_input_delay_seconds), 0)
	var ids: Array[int] = [a_local_commander_id]
	for peer: int in _commander_of_peer:
		var commander: int = int(_commander_of_peer[peer])
		ids.append(commander)
		_acknowledged[commander] = a_first_tick - 1
	_buffer = InputBuffer.new(ids, a_first_tick)
	_sealed_through = a_first_tick - 1
	for t: int in range(a_first_tick, a_first_tick + input_delay_ticks):
		_seal_turn(t)


## Queue the local player's `a_order` for the next sealed turn. An order for another commander
## is refused: a peer only ever speaks for its own slot.
func submit(a_order: PlayerOrder) -> void:
	if a_order.commander_id == local_commander_id:
		_pending.append(a_order)


## Seal the local turn the orders given before `a_tick` apply on: `a_tick` + the input delay.
## Called at the start of every physics frame; a stalled tick is called again, and seals nothing
## new, so an order given while stalled waits for the next tick's turn.
func seal(a_tick: int) -> void:
	if a_tick + input_delay_ticks > _sealed_through:
		_seal_turn(a_tick + input_delay_ticks)


## Take in every packet that has arrived, then send each peer the local turns it has not
## acknowledged and the acknowledgement of its own.
func pump() -> void:
	for message: Array in _transport.receive():
		_take_packet(int(message[0]), message[1])
	for dropped: int in _voted_out:
		_maybe_fence(dropped)
	var votes: Array = _vote_messages()
	for peer: int in _commander_of_peer:
		var commander: int = int(_commander_of_peer[peer])
		if _voted_out.has(commander):
			continue
		var owed: Array[Turn] = []
		for t: Turn in _unacknowledged:
			if t.tick > int(_acknowledged[commander]):
				owed.append(t)
		var packet := TurnPacket.new(
			local_commander_id, _buffer.newest_contiguous(commander), owed, votes
		)
		_transport.send(peer, packet.encode())
	_forget_acknowledged()


## Vote `a_commander_id` out of the match: called by NetMatch once it has waited long enough on
## it. This machine ignores its packets from now on; it forfeits once every peer still playing has
## voted the same.
func vote_out(a_commander_id: int) -> void:
	if a_commander_id == local_commander_id or _voted_out.has(a_commander_id):
		return
	if not _buffer.commander_ids().has(a_commander_id):
		return
	_voted_out[a_commander_id] = _buffer.newest_contiguous(a_commander_id)
	_record_vote(a_commander_id, local_commander_id, int(_voted_out[a_commander_id]))


func has_voted_out(a_commander_id: int) -> bool:
	return _voted_out.has(a_commander_id)


## The tick `a_commander_id` forfeits on, or -1 while it has not been fenced.
func forfeit_tick(a_commander_id: int) -> int:
	return int(_fenced_at.get(a_commander_id, -1))


## Whether `a_tick` may run: every peer's turn for it has arrived.
func can_run(a_tick: int) -> bool:
	return a_tick <= _buffer.confirmed_tick() + RUN_AHEAD_TICKS


## Every peer's orders for `a_tick`, in the one order every peer applies them, and stop holding
## it. Call once, once can_run(a_tick) holds.
func take(a_tick: int) -> Array[PlayerOrder]:
	var orders: Array[PlayerOrder] = _buffer.orders_for(a_tick)
	_buffer.discard_through(a_tick)
	return orders


## The commanders `a_tick` is waiting on — for the waiting-for-player readout.
func waiting_on(a_tick: int) -> Array[int]:
	return _buffer.missing_for(a_tick)


func _seal_turn(a_tick: int) -> void:
	var sealed := Turn.new(a_tick, local_commander_id, _pending)
	_pending = []
	var decoded: Turn = Turn.from_dict(JSON.parse_string(JSON.stringify(sealed.to_dict())))
	_buffer.add(decoded)
	_unacknowledged.append(decoded)
	_sealed_through = a_tick


func _take_packet(a_from: int, a_bytes: PackedByteArray) -> void:
	var packet: TurnPacket = TurnPacket.decode(a_bytes)
	if packet == null or int(_commander_of_peer.get(a_from, -1)) != packet.sender_id:
		return
	# Not a word from a peer this machine has voted out: that is what keeps its vote fixed.
	if _voted_out.has(packet.sender_id):
		return
	_acknowledged[packet.sender_id] = maxi(int(_acknowledged[packet.sender_id]), packet.ack)
	for t: Turn in packet.turns:
		if _buffer.add(t) == InputBuffer.Refusal.CONTRADICTS and contradiction_tick < 0:
			# A peer that sends two different turns for one tick is broken or lying; which one
			# every peer believes is no longer guaranteed.
			contradiction_tick = t.tick
			contradiction_commander = t.commander_id
	for vote: Dictionary in packet.drops:
		var dropped: int = int(vote["commander"])
		# This machine being voted out changes nothing here: the others fence it on their side.
		if dropped == local_commander_id:
			continue
		for t: Turn in vote["turns"]:
			_buffer.add(t)
		_record_vote(dropped, packet.sender_id, int(vote["newest"]))


func _record_vote(a_dropped: int, a_voter: int, a_newest: int) -> void:
	if not _votes.has(a_dropped):
		_votes[a_dropped] = {}
	_votes[a_dropped][a_voter] = a_newest
	_maybe_fence(a_dropped)


## Fence `a_dropped` once this machine has voted it out, every peer still playing has too, and
## this machine holds its turns up to the furthest any vote reached (relayed with the votes).
## TODO: "still playing" is this machine's view; two peers that disagree on who else has gone
## (a network split three ways) can fence at different ticks.
func _maybe_fence(a_dropped: int) -> void:
	if _fenced_at.has(a_dropped) or not _voted_out.has(a_dropped):
		return
	var votes: Dictionary = _votes.get(a_dropped, {})
	for commander: int in _buffer.commander_ids():
		if commander != a_dropped and not _voted_out.has(commander) and not votes.has(commander):
			return
	var furthest: int = -1
	for newest: int in votes.values():
		furthest = maxi(furthest, newest)
	if _buffer.newest_contiguous(a_dropped) < furthest:
		return
	_buffer.fence(a_dropped, furthest + 1)
	_fenced_at[a_dropped] = furthest + 1


## This machine's votes, as sent: each with the dropped peer's turns it holds. A vote stops being
## sent once every peer still playing has RUN its fence tick — which it cannot do unfenced. A turn
## for tick T + delay is sealed at the start of tick T, even while stalled there, so the proof is a
## turn one past that: fence + delay + 1, sealed only once the fence tick has run.
func _vote_messages() -> Array:
	var out: Array = []
	for dropped: int in _voted_out:
		var fence: int = int(_fenced_at.get(dropped, -1))
		if fence >= 0 and _buffer.confirmed_tick() >= fence + input_delay_ticks + 1:
			continue
		(
			out
			. append(
				{
					"commander": dropped,
					"newest": int(_voted_out[dropped]),
					"turns": _buffer.turns_of(dropped),
				}
			)
		)
	return out


## Drop the local turns every peer holds.
func _forget_acknowledged() -> void:
	var held_by_all: int = _sealed_through
	for commander: int in _acknowledged:
		if not _voted_out.has(commander):
			held_by_all = mini(held_by_all, int(_acknowledged[commander]))
	while not _unacknowledged.is_empty() and _unacknowledged[0].tick <= held_by_all:
		_unacknowledged.pop_front()
