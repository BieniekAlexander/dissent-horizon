class_name AvoidanceAgent3D
extends NavigationAgent3D

## A NavigationAgent3D with two layered RVO behaviours:
##
## 1. AVOIDANCE TEAMS. Each commander owns one low avoidance-layer bit
##    (team_bit(commander_id) = 1 << commander_id). A unit broadcasts on its own
##    commander's bit — its identity / "home" channel. By default every unit MASKS
##    every team (plus the pool), so all units avoid all units regardless of team
##    (nobody walks through anybody); the team bit identifies the commander and gives
##    the exception system below a per-commander home channel to return to. (Filtering
##    avoidance by team would, by definition, let other teams pass through each other,
##    so the mask covers every team.)
##
## 2. PER-PAIR EXCEPTIONS. Godot's RVO has no per-instance exclusion list, so to let
##    two specific units ignore each other (the follow mechanic) each excepted agent
##    borrows a unique bit from a high pool and broadcasts ONLY that bit; the partner
##    clears it from its mask. Every other unit keeps all pool bits in its mask, so it
##    still avoids the excepted agent. The avoidance analogue of
##    PhysicsBody3D.add_collision_exception_with().
##
## Bit layout (32 avoidance layers): bits 0..TEAM_BITS-1 are team channels (one per
## commander id, 0..5 today); bits TEAM_BITS..31 are the unique-bit pool. The pool is
## 24 bits, so the cap is ~24 agents in an exception at once (not 24 total).

## Number of low layer bits reserved for commander team channels. Commander ids run
## 0..5 (Commander.id is @export_range(0,5)); 8 leaves margin.
const _TEAM_BITS: int = Commander.NUM_MAX_COMMANDERS
## Mask of every team channel bit (0..TEAM_BITS-1). Kept in each agent's mask so it
## avoids every team, not just its own.
const _ALL_TEAMS: int = (1 << _TEAM_BITS) - 1
## Mask of every unique-bit-pool bit (TEAM_BITS..31). Kept in each agent's mask so it
## keeps avoiding any agent currently broadcasting an exception (pool) bit.
const _POOL_MASK: int = (~((1 << _TEAM_BITS) - 1)) & 0xFFFFFFFF

## Free unique bits (1<<TEAM_BITS .. 1<<31) handed out to agents currently in an
## exception. Static so the whole simulation shares one pool.
static var _free_bits: Array[int] = []
static var _pool_ready: bool = false

## This agent's team channel bit (1 << commander_id), set by enable_avoidance().
var _team_bit: int = 0
## The unique pool bit this agent currently owns, or 0 when it broadcasts on its
## team bit (i.e. has no active exceptions).
var _unique_bit: int = 0
## Set of AvoidanceAgent3D this agent is currently ignoring (mutually).
var _exceptions: Dictionary = {}  # AvoidanceAgent3D -> true


static func _ensure_pool() -> void:
	if _pool_ready:
		return
	for i in range(_TEAM_BITS, 32):  # team bits 0..TEAM_BITS-1 are reserved for teams
		_free_bits.append(1 << i)
	_pool_ready = true


## The avoidance-layer bit for a commander's team.
static func team_bit(commander_id: int) -> int:
	return 1 << clampi(commander_id, 0, _TEAM_BITS - 1)


## Turn on avoidance for the given commander's team. The agent broadcasts on that
## commander's team bit but avoids every team (and any agent in an exception); the
## team bit is its identity / exception home channel, not an avoidance filter.
func enable_avoidance(commander_id: int) -> void:
	avoidance_enabled = true
	_team_bit = team_bit(commander_id)
	avoidance_layers = _broadcast_bit()
	avoidance_mask = _current_mask()


# --- Per-pair exception API ------------------------------------------------

## Make this agent and `other` ignore each other in RVO, leaving every other
## avoidance interaction for both agents unchanged. Idempotent and symmetric.
func add_avoidance_exception_with(other: AvoidanceAgent3D) -> void:
	if other == null or other == self or _exceptions.has(other):
		return
	_ensure_unique_bit()
	other._ensure_unique_bit()
	_exceptions[other] = true
	other._exceptions[self] = true
	_apply_mask()
	other._apply_mask()


## Restore mutual avoidance between this agent and `other`. Idempotent.
func remove_avoidance_exception_with(other: AvoidanceAgent3D) -> void:
	if other == null or not _exceptions.has(other):
		return
	_exceptions.erase(other)
	_apply_mask()
	_maybe_release_bit()
	if is_instance_valid(other):
		other._exceptions.erase(self)
		other._apply_mask()
		other._maybe_release_bit()


## Drop all of this agent's avoidance exceptions, restoring every partner.
func clear_avoidance_exceptions() -> void:
	for other: Variant in _exceptions.keys():
		remove_avoidance_exception_with(other)


# --- Internals -------------------------------------------------------------

## The layer bit this agent broadcasts on: its unique pool bit while excepted,
## otherwise its team bit.
func _broadcast_bit() -> int:
	return _unique_bit if _unique_bit != 0 else _team_bit


## avoidance_mask = every team bit + every pool bit (so all units avoid all units,
## and excepted agents are still avoided), minus the broadcast bit of every agent
## we're ignoring.
func _current_mask() -> int:
	var m: int = _ALL_TEAMS | _POOL_MASK
	for other: Variant in _exceptions.keys():
		if is_instance_valid(other):
			m &= ~(other as AvoidanceAgent3D)._broadcast_bit()
	return m


func _apply_mask() -> void:
	avoidance_mask = _current_mask()


## Borrow a unique bit from the pool (lazily) so partners can single this agent
## out. No-op once owned; degrades to staying on the team bit if the pool is empty.
func _ensure_unique_bit() -> void:
	if _unique_bit != 0:
		return
	_ensure_pool()
	if _free_bits.is_empty():
		push_warning("AvoidanceAgent3D: avoidance bit pool exhausted (>%d concurrent exceptions); pair not fully isolated" % (32 - _TEAM_BITS))
		return
	_unique_bit = _free_bits.pop_back()
	avoidance_layers = _unique_bit


## Return our unique bit to the pool once we have no exceptions left.
func _maybe_release_bit() -> void:
	if _unique_bit != 0 and _exceptions.is_empty():
		_free_bits.append(_unique_bit)
		_unique_bit = 0
		avoidance_layers = _team_bit


func _notification(what: int) -> void:
	# On free, restore every partner's mask and return our bit, so a recycled bit
	# can't leave a stale exception on another agent.
	if what == NOTIFICATION_PREDELETE:
		clear_avoidance_exceptions()
