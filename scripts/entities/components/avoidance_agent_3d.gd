class_name AvoidanceAgent3D
extends NavigationAgent3D

## A NavigationAgent3D with two layered RVO behaviours:
##
## 1. SAME-TEAM RECIPROCAL RVO. Each commander owns one low layer bit
##    (team_bit(id) = 1 << id, bits 0..TEAM_BITS-1). A unit broadcasts on its
##    team bit and masks ONLY its own team bit, so same-team agents do standard
##    reciprocal RVO with each other (both adjust).
##
## 2. CROSS-TEAM ONE-SIDED AVOIDANCE (via NavigationObstacle3D). Each unit also
##    carries a NavigationObstacle3D whose avoidance_layers = obstacle_bit(id)
##    (bits TEAM_BITS..2*TEAM_BITS-1). A unit's avoidance_mask includes all
##    FOREIGN obstacle bits but NOT the enemy's agent bit, so the unit steers
##    around the enemy's obstacle unilaterally without triggering reciprocal RVO.
##    The obstacle's layers are wired in Commandable._on_commander_changed.
##
## 3. PER-PAIR EXCEPTIONS (follow mechanic). Godot's RVO has no per-instance
##    exclusion list; each excepted agent borrows a unique bit from the high pool
##    (bits POOL_START..31) and broadcasts only that bit; the partner clears it
##    from its mask. All other agents still mask every pool bit so they keep
##    avoiding the excepted agent.
##
## Bit layout (32 avoidance layers):
##   bits  0.. 7 — agent team channels (one per commander id, 0..7)
##   bits  8..15 — obstacle channels   (one per commander id, shifted by TEAM_BITS)
##   bits 16..31 — per-pair exception pool

#region Constants
## Number of low layer bits reserved for commander team channels.
const _TEAM_BITS: int = Commander.NUM_MAX_COMMANDERS  ## = 8
## Mask of every team-channel bit (bits 0..TEAM_BITS-1).
const _ALL_TEAMS: int = (1 << _TEAM_BITS) - 1
## Mask of every obstacle-channel bit (bits TEAM_BITS..2*TEAM_BITS-1).
const _ALL_OBSTACLES: int = _ALL_TEAMS << _TEAM_BITS
## First bit of the exception pool.
const _POOL_START: int = 2 * _TEAM_BITS  ## = 16
## Mask of every exception-pool bit (bits POOL_START..31).
const _POOL_MASK: int = (~((1 << _POOL_START) - 1)) & 0xFFFFFFFF
#endregion

#region Properties
## Free unique bits (bits POOL_START..31) handed out to agents in an exception.
static var _free_bits: Array[int] = []
static var _pool_ready: bool = false

## This agent's team channel bit (1 << commander_id), set by enable_avoidance().
var _team_bit: int = 0
## The unique pool bit this agent currently owns, or 0 (broadcasts on team bit).
var _unique_bit: int = 0
## Set of AvoidanceAgent3D this agent is currently ignoring (mutually).
var _exceptions: Dictionary = {}  # AvoidanceAgent3D -> true
#endregion

#region Static helpers
static func _ensure_pool() -> void:
	if _pool_ready:
		return
	for i: int in range(_POOL_START, 32):
		_free_bits.append(1 << i)
	_pool_ready = true


## The avoidance-layer bit for a commander's agent channel (bits 0..7).
static func team_bit(commander_id: int) -> int:
	return 1 << clampi(commander_id, 0, _TEAM_BITS - 1)


## The avoidance-layer bit for a commander's NavigationObstacle3D (bits 8..15).
## Used by Commandable._on_commander_changed to configure the obstacle node.
static func obstacle_bit(commander_id: int) -> int:
	return 1 << (_TEAM_BITS + clampi(commander_id, 0, _TEAM_BITS - 1))
#endregion

#region Public API
## Turn on avoidance for the given commander's team. The agent broadcasts on
## that commander's team bit and masks own-team agents + all foreign obstacles +
## the exception pool. Same-team pairs get reciprocal RVO; cross-team avoidance
## is one-sided via NavigationObstacle3D (see Commandable._on_commander_changed).
func enable_avoidance(commander_id: int) -> void:
	avoidance_enabled = true
	_team_bit = team_bit(commander_id)
	avoidance_layers = _broadcast_bit()
	avoidance_mask = _current_mask()


#region Per-pair exceptions
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
#endregion

#endregion

#region Private helpers
## The layer bit this agent broadcasts on: its unique pool bit while excepted,
## otherwise its team bit.
func _broadcast_bit() -> int:
	return _unique_bit if _unique_bit != 0 else _team_bit


## The obstacle-channel bit for this agent's own commander (bits 8..15).
func _own_obstacle_bit() -> int:
	return _team_bit << _TEAM_BITS


## Obstacle bits for every commander EXCEPT this agent's own commander.
## An agent avoids foreign obstacles (one-sided) but not its own obstacle
## (which is co-located with the agent and would cause degenerate avoidance).
func _foreign_obstacle_mask() -> int:
	return _ALL_OBSTACLES & ~_own_obstacle_bit()


## avoidance_mask = own team bit (same-team reciprocal RVO)
##               + all foreign obstacle bits (cross-team one-sided avoidance)
##               + all pool bits (so excepted agents remain visible)
##               - broadcast bit of every agent we're ignoring.
func _current_mask() -> int:
	var m: int = _team_bit | _foreign_obstacle_mask() | _POOL_MASK
	for other: Variant in _exceptions.keys():
		if is_instance_valid(other):
			m &= ~(other as AvoidanceAgent3D)._broadcast_bit()
	return m


func _apply_mask() -> void:
	avoidance_mask = _current_mask()


## Borrow a unique bit from the pool (lazily) so partners can single this agent
## out. No-op once owned; degrades gracefully if the pool is empty.
func _ensure_unique_bit() -> void:
	if _unique_bit != 0:
		return
	_ensure_pool()
	if _free_bits.is_empty():
		push_warning("AvoidanceAgent3D: avoidance bit pool exhausted (>%d concurrent exceptions); pair not fully isolated" % (32 - _POOL_START))
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
	if what == NOTIFICATION_PREDELETE:
		clear_avoidance_exceptions()
#endregion
