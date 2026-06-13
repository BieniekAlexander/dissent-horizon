class_name AvoidanceAgent3D
extends NavigationAgent3D

## A NavigationAgent3D that supports per-pair RVO avoidance exceptions — the
## avoidance analogue of PhysicsBody3D.add_collision_exception_with().
##
## Godot's RVO has no per-instance exclusion list; agents only filter neighbours
## by the avoidance_layers / avoidance_mask bitmasks. To let two specific agents
## ignore each other *without* affecting anyone else, each agent that enters an
## exception is handed a unique layer bit, and the partner clears that bit from
## its own mask. Everyone else keeps mask = ALL, so all other interactions are
## untouched.
##
## Bits are pooled: a non-excepted agent broadcasts on the shared NORMAL bit and
## only borrows a unique bit while it actually has an exception, returning it
## afterwards. The pool is 31 bits, so the cap is ~31 agents in an exception at
## once (not 31 agents total). If the pool is exhausted the exception degrades
## gracefully (a warning, and the agents fall back to mutual avoidance).

## Shared channel every non-excepted agent broadcasts on; everyone's mask
## includes it, so by default all agents avoid all agents.
const _NORMAL_BIT: int = 1 << 0
## "Avoid everything" mask. Exceptions clear individual partner bits from it.
const _ALL: int = 0xFFFFFFFF

## Free unique bits (1<<1 .. 1<<31) handed out to agents currently in an
## exception. Static so the whole simulation shares one pool.
static var _free_bits: Array[int] = []
static var _pool_ready: bool = false

## The unique bit this agent currently owns, or 0 when it broadcasts on the
## shared NORMAL bit (i.e. has no active exceptions).
var _unique_bit: int = 0
## Set of AvoidanceAgent3D this agent is currently ignoring (mutually).
var _exceptions: Dictionary = {}  # AvoidanceAgent3D -> true


static func _ensure_pool() -> void:
	if _pool_ready:
		return
	for i in range(1, 32):  # bits 1..31; bit 0 is the shared NORMAL channel
		_free_bits.append(1 << i)
	_pool_ready = true


## Turn on avoidance with the default "avoid everyone" configuration. Call once
## the agent should participate in the RVO simulation.
func enable_avoidance() -> void:
	avoidance_enabled = true
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

## The layer bit this agent broadcasts on: its unique bit while excepted,
## otherwise the shared NORMAL bit.
func _broadcast_bit() -> int:
	return _unique_bit if _unique_bit != 0 else _NORMAL_BIT


## avoidance_mask = ALL minus the broadcast bit of every agent we're ignoring.
func _current_mask() -> int:
	var m: int = _ALL
	for other: Variant in _exceptions.keys():
		if is_instance_valid(other):
			m &= ~(other as AvoidanceAgent3D)._broadcast_bit()
	return m


func _apply_mask() -> void:
	avoidance_mask = _current_mask()


## Borrow a unique bit from the pool (lazily) so partners can single this agent
## out. No-op once owned; degrades to staying on NORMAL if the pool is empty.
func _ensure_unique_bit() -> void:
	if _unique_bit != 0:
		return
	_ensure_pool()
	if _free_bits.is_empty():
		push_warning("AvoidanceAgent3D: avoidance bit pool exhausted (>31 concurrent exceptions); pair not fully isolated")
		return
	_unique_bit = _free_bits.pop_back()
	avoidance_layers = _unique_bit


## Return our unique bit to the pool once we have no exceptions left.
func _maybe_release_bit() -> void:
	if _unique_bit != 0 and _exceptions.is_empty():
		_free_bits.append(_unique_bit)
		_unique_bit = 0
		avoidance_layers = _NORMAL_BIT


func _notification(what: int) -> void:
	# On free, restore every partner's mask and return our bit, so a recycled bit
	# can't leave a stale exception on another agent.
	if what == NOTIFICATION_PREDELETE:
		clear_avoidance_exceptions()
