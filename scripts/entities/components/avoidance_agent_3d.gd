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
##    The obstacle's layers are wired in Actor._on_commander_changed.
##
## 3. PLANTED (a unit performing an action). A unit that is acting — firing, building,
##    repairing, unloading, interacting — leaves RVO entirely: it broadcasts nothing and masks
##    nothing, so nobody does reciprocal RVO with it and nothing pushes it, while Movement
##    moves its obstacle onto the STANDING channel, so every agent of every team, its own
##    included, steers round it one-sided (Alex, 2026-10-18). See set_planted.
##
## 4. PER-PAIR EXCEPTIONS (follow mechanic). Godot's RVO has no per-instance
##    exclusion list; each excepted agent borrows a unique bit from the high pool
##    (bits POOL_START..31) and broadcasts only that bit; the partner clears it
##    from its mask. All other agents still mask every pool bit so they keep
##    avoiding the excepted agent.
##
## Bit layout (32 avoidance layers):
##   bits  0.. 7 — agent team channels (one per commander id, 0..7)
##   bits  8..15 — obstacle channels   (one per commander id, shifted by TEAM_BITS)
##   bits 16..30 — per-pair exception pool
##   bit  31     — the STANDING channel: a piece that has planted itself (a deployed unit,
##                 see Deployable) broadcasts its obstacle here. It is never handed out as
##                 an exception bit, and every agent masks the whole pool range, so every
##                 agent of every team steers around a standing piece one-sided.


#region Lifecycle
## Never paused with the world. A paused agent is taken out of the navigation server's avoidance
## and put back on resume, and that changes the avoidance it solves afterwards: any hold — a
## dialog, the pause menu, a network stall — would play a different match from one never held.
## Instead the whole navigation server is switched off for a hold (SimulationClock), so a kept
## agent computes nothing while held. The obstacle component is kept running for the same reason
## (avoidance_obstacle.tscn); test_ReplayRoundTrip holds a match through stalls and requires its
## playback to match.
func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	velocity_computed.connect(func(a_safe: Vector3) -> void: last_safe_velocity = a_safe)


#endregion

#region Constants
## Number of low layer bits reserved for commander team channels.
const _TEAM_BITS: int = Commander.NUM_MAX_COMMANDERS  ## = 8
## Mask of every team-channel bit (bits 0..TEAM_BITS-1).
const _ALL_TEAMS: int = (1 << _TEAM_BITS) - 1
## Mask of every obstacle-channel bit (bits TEAM_BITS..2*TEAM_BITS-1).
const _ALL_OBSTACLES: int = _ALL_TEAMS << _TEAM_BITS
## First bit of the exception pool.
const _POOL_START: int = 2 * _TEAM_BITS  ## = 16
## Mask of every bit from POOL_START up: the exception pool AND the standing channel, which
## is why masking it makes every agent avoid a standing piece.
const _POOL_MASK: int = (~((1 << _POOL_START) - 1)) & 0xFFFFFFFF
## The obstacle channel a standing piece broadcasts on — the top bit, withheld from the pool.
const STANDING_OBSTACLE_BIT: int = 1 << 31
#endregion

#region Properties
## Free unique bits (bits POOL_START..31) handed out to agents in an exception.
static var _free_bits: Array[int] = []
static var _pool_ready: bool = false
## Every agent in the tree, and whether the server's avoidance list may be out of canonical order
## since settle_order last ran. Static: there is one navigation server.
static var _registry: Array = []
static var _is_order_dirty: bool = true

## This agent's team channel bit (1 << commander_id), set by enable_avoidance().
var _team_bit: int = 0
## The unique pool bit this agent currently owns, or 0 (broadcasts on team bit).
var _unique_bit: int = 0
## Set of AvoidanceAgent3D this agent is currently ignoring (mutually).
var _exceptions: Dictionary = {}  # AvoidanceAgent3D -> true

## The velocity avoidance last handed back: the navigation server's current velocity for this
## agent, which its neighbours avoid, and which the server will not report (agent_get_velocity
## answers with the velocity asked for). What a snapshot's restore puts back (SimulationSnapshot).
var last_safe_velocity: Vector3 = Vector3.ZERO

## Whether this agent is PLANTED (see the class doc, 3): out of RVO both ways.
var _is_planted: bool = false

## Foreign obstacle bits (see obstacle_bit()) currently excluded from this agent's
## mask because Actor._update_crush_avoidance_exclusions() found at least one
## nearby enemy on that channel this agent can crush (Movement.can_crush) — the
## agent should path through it rather than detour around it. 0 = nothing excluded.
## CAVEAT: an obstacle channel is shared by an entire commander's units, not one
## unit, so excluding it also hides that commander's OTHER, non-crushable obstacles
## while a crushable one is nearby. There is no per-unit obstacle bit today (the
## exception pool at POOL_START.. is agent-to-agent only, see add_avoidance_exception_with);
## this is a team-wide approximation, not a precise per-enemy exclusion.
var _crush_excluded_obstacles: int = 0
#endregion

#endregion


#region Avoidance order
## Put the navigation server's avoidance agents in spawn-serial order, when any has joined, left or
## been switched since the last time. Called at the start of every frame (OrderStream), and by a
## snapshot's restore with `is_forced`.
##
## Why: the server steps avoidance one agent at a time, each agent's new velocity written back
## before the next is computed, so the ORDER of its agent list decides what neighbours do — and
## that list, kept by appending and by swap-removal, can be neither read nor set. Kept in a
## canonical order, it is the same on every run and can be rebuilt by a restore
## (gdd/systems/commands/saved-games.md §The snapshot). Each agent is switched off, then on again
## in order, and handed its wanted velocity again, which switching on overwrites.
static func settle_order(is_forced: bool = false) -> void:
	if not (_is_order_dirty or is_forced):
		return
	_is_order_dirty = false
	var active: Array = _registry.filter(
		func(agent: Variant) -> bool:
			return (
				is_instance_valid(agent)
				and (agent as AvoidanceAgent3D).avoidance_enabled
				and Entity.owning(agent as Node) != null
			)
	)
	active.sort_custom(
		func(a: AvoidanceAgent3D, b: AvoidanceAgent3D) -> bool:
			return Entity.owning(a).identity_key() < Entity.owning(b).identity_key()
	)
	for agent: AvoidanceAgent3D in active:
		NavigationServer3D.agent_set_avoidance_enabled(agent.get_rid(), false)
	for agent: AvoidanceAgent3D in active:
		NavigationServer3D.agent_set_avoidance_enabled(agent.get_rid(), true)
		NavigationServer3D.agent_set_velocity(agent.get_rid(), agent.velocity)


#endregion


#region Static helpers
## The free exception bits, in the order they are handed out, for a snapshot: which bit an agent
## takes next decides which agents avoid which (SimulationSnapshot).
static func snapshot_pool() -> Array:
	_ensure_pool()
	return Array(_free_bits)


static func restore_pool(bits: Array) -> void:
	_pool_ready = true
	_free_bits.assign(bits.map(func(bit: Variant) -> int: return int(bit)))


static func _ensure_pool() -> void:
	if _pool_ready:
		return
	for i: int in range(_POOL_START, 32):
		if (1 << i) != STANDING_OBSTACLE_BIT:
			_free_bits.append(1 << i)
	_pool_ready = true


## The avoidance-layer bit for a commander's agent channel (bits 0..7).
static func team_bit(commander_id: int) -> int:
	return 1 << clampi(commander_id, 0, _TEAM_BITS - 1)


## The avoidance-layer bit for a commander's NavigationObstacle3D (bits 8..15).
## Used by Actor._on_commander_changed to configure the obstacle node.
static func obstacle_bit(commander_id: int) -> int:
	return 1 << (_TEAM_BITS + clampi(commander_id, 0, _TEAM_BITS - 1))


#endregion


#region Public API
## Turn on avoidance for the given commander's team. The agent broadcasts on
## that commander's team bit and masks own-team agents + all foreign obstacles +
## the exception pool. Same-team pairs get reciprocal RVO; cross-team avoidance
## is one-sided via NavigationObstacle3D (see Actor._on_commander_changed).
func enable_avoidance(a_commander_id: int) -> void:
	avoidance_enabled = true
	_is_order_dirty = true
	_team_bit = team_bit(a_commander_id)
	avoidance_layers = _broadcast_bit()
	avoidance_mask = _current_mask()


#region Per-pair exceptions
## Make this agent and `other` ignore each other in RVO, leaving every other
## avoidance interaction for both agents unchanged. Idempotent and symmetric.
func add_avoidance_exception_with(a_other: AvoidanceAgent3D) -> void:
	if a_other == null or a_other == self or _exceptions.has(a_other):
		return
	_ensure_unique_bit()
	a_other._ensure_unique_bit()
	_exceptions[a_other] = true
	a_other._exceptions[self] = true
	_apply_mask()
	a_other._apply_mask()


## Restore mutual avoidance between this agent and `other`. Idempotent.
func remove_avoidance_exception_with(a_other: AvoidanceAgent3D) -> void:
	if a_other == null or not _exceptions.has(a_other):
		return
	_exceptions.erase(a_other)
	_apply_mask()
	_maybe_release_bit()
	if is_instance_valid(a_other):
		a_other._exceptions.erase(self)
		a_other._apply_mask()
		a_other._maybe_release_bit()


## Drop all of this agent's avoidance exceptions, restoring every partner.
func clear_avoidance_exceptions() -> void:
	for other: Variant in _exceptions.keys():
		remove_avoidance_exception_with(other)


#endregion


#region Planting
## Take this agent out of RVO (`a_planted`) or put it back: planted, it broadcasts on no layer
## and masks none. Its OBSTACLE is Movement's to move onto the standing channel. Idempotent.
func set_planted(a_planted: bool) -> void:
	if a_planted == _is_planted:
		return
	_is_planted = a_planted
	avoidance_layers = _broadcast_bit()
	_apply_mask()


func is_planted() -> bool:
	return _is_planted


#endregion


#region Crush exclusion
## Set which foreign obstacle bits (see obstacle_bit()) to drop from avoidance_mask
## because every nearby enemy currently on that channel is one this agent can crush
## (see the _crush_excluded_obstacles caveat above). Pass 0 to clear. Called every
## tick by Actor._update_crush_avoidance_exclusions(); a no-op when unchanged.
func set_crush_excluded_obstacles(a_mask: int) -> void:
	if a_mask == _crush_excluded_obstacles:
		return
	_crush_excluded_obstacles = a_mask
	_apply_mask()


#endregion

#endregion


#region Private helpers
## The layer bit this agent broadcasts on: its unique pool bit while excepted,
## otherwise its team bit.
func _broadcast_bit() -> int:
	if _is_planted:
		return 0
	return _unique_bit if _unique_bit != 0 else _team_bit


## The obstacle-channel bit for this agent's own commander (bits 8..15).
func _own_obstacle_bit() -> int:
	return _team_bit << _TEAM_BITS


## Obstacle bits for every commander EXCEPT this agent's own commander.
## An agent avoids foreign obstacles (one-sided) but not its own obstacle
## (which is co-located with the agent and would cause degenerate avoidance).
func _foreign_obstacle_mask() -> int:
	return _ALL_OBSTACLES & ~_own_obstacle_bit()


## avoidance_mask = nothing while planted; otherwise
##               own team bit (same-team reciprocal RVO)
##               + all foreign obstacle bits (cross-team one-sided avoidance)
##               + all pool bits (so excepted agents remain visible)
##               - broadcast bit of every agent we're ignoring.
func _current_mask() -> int:
	if _is_planted:
		return 0
	var m: int = _team_bit | _foreign_obstacle_mask() | _POOL_MASK
	for other: Variant in _exceptions.keys():
		if is_instance_valid(other):
			m &= ~(other as AvoidanceAgent3D)._broadcast_bit()
	m &= ~_crush_excluded_obstacles
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
		push_warning(
			(
				(
					"AvoidanceAgent3D: avoidance bit pool exhausted (>%d concurrent exceptions);"
					+ " pair not fully isolated"
				)
				% (31 - _POOL_START)
			)
		)
		return
	_unique_bit = _free_bits.pop_back()
	avoidance_layers = _broadcast_bit()


## Return our unique bit to the pool once we have no exceptions left.
func _maybe_release_bit() -> void:
	if _unique_bit != 0 and _exceptions.is_empty():
		_free_bits.append(_unique_bit)
		_unique_bit = 0
		avoidance_layers = _broadcast_bit()


## Turn avoidance off: the agent leaves the server's avoidance list until enable_avoidance.
func disable_avoidance() -> void:
	avoidance_enabled = false
	_is_order_dirty = true


func _notification(a_what: int) -> void:
	match a_what:
		NOTIFICATION_PREDELETE:
			clear_avoidance_exceptions()
		NOTIFICATION_ENTER_TREE:
			_registry.append(self)
			_is_order_dirty = true
		NOTIFICATION_EXIT_TREE:
			_registry.erase(self)
			_is_order_dirty = true
		NOTIFICATION_PAUSED, NOTIFICATION_UNPAUSED:
			_is_order_dirty = true
#endregion
