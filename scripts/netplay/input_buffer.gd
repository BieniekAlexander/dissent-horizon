class_name InputBuffer
extends RefCounted

## Every commander's turns, by tick: the core data structure of lockstep, and of every rollback
## library. A tick is CONFIRMED once every commander's turn for it has arrived; lockstep runs a
## tick only once it is confirmed, and rollback (later) runs ahead of the newest confirmed tick
## and re-runs from a snapshot when a turn arrives that differs from what it stood in for.
## gdd/systems/commands/netplay.md §The model, §What lockstep builds that rollback keeps.
##
## Topology-free: it does not know which turns are local and which came over a wire. The same
## commander set on every peer, and the same order of application, are what make every peer
## apply the same tick identically: orders_for() returns a tick's orders by commander id, then in
## the order each player gave them.
##
## Driven by Lockstep.
## A commander who forfeits is FENCED at an agreed tick (fence()): from it on the buffer stands in
## its turns itself — a FORFEIT order on the fence tick, empty turns after — and ignores any the
## commander sends, so the others play on without it (netplay.md §Decisions, a silent peer).

## Why add() refused a turn.
enum Refusal {
	NONE,
	UNKNOWN_COMMANDER,  ## not one of this match's slots
	TOO_OLD,  ## for a tick already discarded
	CONTRADICTS,  ## differs from the turn already held for that slot and tick
}

## The tick the match starts on; no turn before it is ever held or waited for.
var first_tick: int
## Turns by tick, then by commander id.
var _turns: Dictionary = {}
## Per commander: the newest tick up to which every turn from first_tick has arrived.
var _contiguous: Dictionary = {}
## Ticks below this were discarded and are no longer held.
var _floor: int
var _commander_ids: Array[int] = []
## Commander id -> the tick it forfeits on.
var _fences: Dictionary = {}

## What newest_contiguous reads for a fenced commander once every turn before its fence is in: it
## never holds a tick back again.
const _FENCED_THROUGH: int = 2147483647


func _init(a_commander_ids: Array[int] = [], a_first_tick: int = 0) -> void:
	first_tick = a_first_tick
	_floor = a_first_tick
	_commander_ids = a_commander_ids.duplicate()
	_commander_ids.sort()
	for id: int in _commander_ids:
		_contiguous[id] = a_first_tick - 1


func commander_ids() -> Array[int]:
	return _commander_ids.duplicate()


## Hold `a_turn`. A copy of a turn already held is accepted and changes nothing — a resend is
## normal on a lossy link. Returns why it was refused, or Refusal.NONE.
func add(a_turn: Turn) -> Refusal:
	if not _contiguous.has(a_turn.commander_id):
		return Refusal.UNKNOWN_COMMANDER
	if a_turn.tick < _floor:
		return Refusal.TOO_OLD
	if _fences.has(a_turn.commander_id) and a_turn.tick >= int(_fences[a_turn.commander_id]):
		return Refusal.NONE
	var held: Turn = turn(a_turn.tick, a_turn.commander_id)
	if held != null:
		return Refusal.NONE if held.same_as(a_turn) else Refusal.CONTRADICTS
	if not _turns.has(a_turn.tick):
		_turns[a_turn.tick] = {}
	_turns[a_turn.tick][a_turn.commander_id] = a_turn
	_advance(a_turn.commander_id)
	return Refusal.NONE


func has_turn(a_tick: int, a_commander_id: int) -> bool:
	return turn(a_tick, a_commander_id) != null


## The turn held for that slot and tick, or null. A fenced commander's from its fence on are
## stood in: a FORFEIT order on the fence tick, nothing after.
func turn(a_tick: int, a_commander_id: int) -> Turn:
	if _fences.has(a_commander_id) and a_tick >= int(_fences[a_commander_id]):
		var orders: Array[PlayerOrder] = []
		if a_tick == int(_fences[a_commander_id]):
			orders.append(PlayerOrder.new(PlayerOrder.Kind.FORFEIT, a_commander_id))
		return Turn.new(a_tick, a_commander_id, orders)
	var by_commander: Dictionary = _turns.get(a_tick, {})
	return by_commander.get(a_commander_id, null)


## The turns of `a_commander_id` this buffer holds, by tick — what a vote to drop it relays.
func turns_of(a_commander_id: int) -> Array[Turn]:
	var out: Array[Turn] = []
	var ticks: Array = _turns.keys()
	ticks.sort()
	for tick: int in ticks:
		var held: Turn = (_turns[tick] as Dictionary).get(a_commander_id, null)
		if held != null:
			out.append(held)
	return out


## Fence `a_commander_id` at `a_tick`: it forfeits there, and its turns are stood in from then on.
## Once only, and only for a commander of this match.
func fence(a_commander_id: int, a_tick: int) -> void:
	if not _contiguous.has(a_commander_id) or _fences.has(a_commander_id):
		return
	_fences[a_commander_id] = a_tick
	_advance(a_commander_id)


func is_fenced(a_commander_id: int) -> bool:
	return _fences.has(a_commander_id)


## The newest tick up to which every turn of `a_commander_id` has arrived; first_tick - 1 while
## none has.
func newest_contiguous(a_commander_id: int) -> int:
	return int(_contiguous.get(a_commander_id, first_tick - 1))


## The newest tick every commander's turn has arrived for, and every tick before it.
func confirmed_tick() -> int:
	var newest: int = 2147483647
	for id: int in _commander_ids:
		newest = mini(newest, newest_contiguous(id))
	return first_tick - 1 if _commander_ids.is_empty() else newest


func is_confirmed(a_tick: int) -> bool:
	return a_tick <= confirmed_tick()


## The commanders whose turn for `a_tick` has not arrived — who a stalled tick is waiting on.
func missing_for(a_tick: int) -> Array[int]:
	var out: Array[int] = []
	for id: int in _commander_ids:
		if not has_turn(a_tick, id):
			out.append(id)
	return out


## Every order for `a_tick`, in the one order every peer applies them: by commander id, then as
## each player gave them. Empty for a tick not yet confirmed — never part of one.
func orders_for(a_tick: int) -> Array[PlayerOrder]:
	var out: Array[PlayerOrder] = []
	if not is_confirmed(a_tick):
		return out
	for id: int in _commander_ids:
		var held: Turn = turn(a_tick, id)
		if held != null:
			out.append_array(held.orders)
	return out


## Stop holding every tick up to and including `a_tick` (they have been applied). A turn for one
## of them that arrives later is refused as TOO_OLD.
func discard_through(a_tick: int) -> void:
	for t: int in range(_floor, a_tick + 1):
		_turns.erase(t)
	_floor = maxi(_floor, a_tick + 1)


func _advance(a_commander_id: int) -> void:
	var next: int = int(_contiguous[a_commander_id]) + 1
	var fenced_at: int = int(_fences.get(a_commander_id, _FENCED_THROUGH))
	while next < fenced_at and (has_turn(next, a_commander_id) or next < _floor):
		next += 1
	_contiguous[a_commander_id] = _FENCED_THROUGH if next >= fenced_at else next - 1
