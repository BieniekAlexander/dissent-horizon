class_name CommandReceiver
extends RefCounted

#region Constants
enum Disposition {
	PASSIVE,
	AGGRESSIVE
}
#endregion

#region Properties
var owner: Commandable

## The active command. Assigning it is the single chokepoint for group-move speed-cap
## cleanup (see _release_speed_cap): every path that starts, swaps, or drops a command
## goes through here, so the cap can be released at a moment when `owner` is known to be
## fully alive. It deliberately does NOT live in MoveCommand's destructor — see there.
var _command: MoveCommand = null:
	set(value):
		var outgoing: MoveCommand = _command
		_command = value
		if value != null:
			value.has_been_active = true
		# The cap belongs to whichever command was driving us. Release it only once that
		# command has genuinely LEFT this receiver — not when an interrupt has merely
		# pushed it into the queue, since it will resume later and should keep its pace.
		# Callers that displace a command into the queue do so before assigning here, so
		# the queue check below sees it.
		if outgoing != null and not is_same(outgoing, value) \
				and not _command_queue.has(outgoing):
			_release_speed_cap()
			# Same moment, same test: the command has left for good rather than been pushed
			# aside, so anything it was holding on the world's behalf (a Spot's beacon) is
			# released here — while `owner` is still fully alive.
			outgoing.on_released(owner)

var _command_queue: Array[MoveCommand] = []
var _disposition: Disposition = Disposition.PASSIVE

## The unit currently being followed and the command driving that follow, both
## captured while the target is still valid. Needed because a freed reference
## reads as null in Godot (== null is true), so once the followed unit dies its
## death is indistinguishable from a plain terrain move unless we remembered it.
var _followed: Commandable = null
var _follow_cmd: MoveCommand = null

## Memoized approach to a structure target: which command it was resolved for, and the cell.
## Resolving it asks the navigation server for a path per candidate cell (see
## _resolve_structure_approach), too costly to repeat every tick for every unit walking to a
## building, and a structure does not move, so one answer holds for the command's life.
var _approach_command: MoveCommand = null
var _approach_cell: Vector2i = Vector2i(-1, -1)
#endregion

#region Public API
func initialize(a_owner: Commandable) -> void:
	owner = a_owner
	_command_queue = []

## Drop the group-move speed cap set by RTSController.assign_command_to_units, so a unit whose
## group order has ended goes back to its own speed.
##
## Driven by the `_command` setter rather than by MoveCommand's PREDELETE, where it used to
## sit: a destructor runs during a dying unit's own teardown, and reading its components there
## dereferences freed memory. Why, and the segfault that taught it:
## gdd/systems/combat/bombardment.md §on_released.
func _release_speed_cap() -> void:
	if owner != null and is_instance_valid(owner) and owner.movement != null:
		owner.movement.speed_cap = 0.0

func has_pending_work() -> bool:
	return _command != null or not _command_queue.is_empty()

## Returns the active command followed by any queued commands, in execution order.
func get_command_chain() -> Array[MoveCommand]:
	var chain: Array[MoveCommand] = []
	if _command != null:
		chain.append(_command)
	chain.append_array(_command_queue)
	return chain

## The part of this receiver's command chain that [a_recipient] could carry out, as fresh
## copies — for a unit TRANSFORMATION, where the piece changes but the player's standing
## orders should survive it.
##
## TRUNCATES at the first command the recipient cannot perform rather than filtering it out,
## because a queue is a SEQUENCE. The commands are DUPLICATED rather than handed over, the
## same treatment rally templates get. Why both:
## gdd/systems/macroeconomics/sanctions/payloads.md §A transformation carries the unit's
## orders.
func portable_chain_for(a_recipient: Commandable) -> Array[MoveCommand]:
	var portable: Array[MoveCommand] = []
	for command: MoveCommand in get_command_chain():
		if not CommandContextParser.actor_can_perform(a_recipient, command):
			break
		portable.append(command.duplicated())
	return portable


## True when the unit has no user-set command — either genuinely idle or only
## running the fallback placeholder. Queued commands count as non-idle.
func is_idle() -> bool:
	return _command_queue.is_empty() and (_command == null)

## Stand down the ACTIVE order if it only makes sense with ammunition: push it to the front
## of the queue and stop driving it. Reports whether anything moved.
##
## DEFERRED, NOT DISCARDED — and pushing it into the queue BEFORE clearing `_command` is what
## makes it an interrupt rather than a release. Anything already QUEUED is left alone; it was
## never being driven. Why:
## gdd/systems/combat/aerial-operations/rearm-and-resupply.md §Breaking off and resuming.
func defer_ammo_dependent_commands() -> bool:
	if _command == null or not _command.requires_ammo():
		return false
	_command_queue.push_front(_command)
	_command = null
	return true


## True when there is no order being driven and everything waiting is one this unit cannot
## carry out without ammunition — i.e. nothing it could usefully be doing instead of flying
## home. The gate on the automatic return to an airfield.
##
## Deliberately not `is_idle()`: an order just deferred by defer_ammo_dependent_commands is
## sitting in the queue, so the unit is not idle, and it must still go and rearm. Equally
## deliberately not "no active command": a plain move waiting to be popped is real work, and
## putting a Rearm in front of it would override an order the player gave.
func awaiting_only_ammo_dependent_work() -> bool:
	if _command != null:
		return false
	for queued: MoveCommand in _command_queue:
		if not queued.requires_ammo():
			return false
	return true

func has_patrol_command() -> bool:
	if _command is Patrol:
		return true
	for cmd: MoveCommand in _command_queue:
		if cmd is Patrol:
			return true
	return false

## Pops and returns the positions of every leading Patrol command from the front
## of the queue (stopping at the first non-Patrol entry). Used by Patrol.fulfill_action
## to absorb Shift+Patrol waypoints at arrival time.
func consume_leading_patrol_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	var queued_before: Array[MoveCommand] = _command_queue.duplicate()
	while not _command_queue.is_empty():
		var front: MoveCommand = _command_queue.front()
		if front is Patrol:
			positions.append((front as Patrol).message.position)
			_command_queue.pop_front()
		else:
			break
	_release_dropped(queued_before)
	return positions


## Call on_released on every command in `a_before` this receiver no longer holds, in either the
## queue or the active slot. The `_command` setter does this for the ACTIVE command; this is the
## same hook for QUEUED ones, which otherwise left without a word — an Occupy displaced by an
## interrupt and then dropped kept its unit's collision exception with the host.
func _release_dropped(a_before: Array[MoveCommand]) -> void:
	for dropped: MoveCommand in a_before:
		if dropped.has_been_active and not is_same(dropped, _command) \
				and not _command_queue.has(dropped):
			dropped.on_released(owner)

func load_destination(a_command: MoveCommand) -> void:
	if owner.can_move():
		owner.locomotion.set_goal(_resolve_movement_target(a_command), _arrival_for(a_command))

## The nav-mesh point a command should actually walk toward. For a structure
## target, that's the structure's footprint-adjacent cell closest to THIS actor
## — not the structure's own footprint centroid (message.position), which may
## sit on a non-navigable cell and, being the same for every actor, would pull
## everyone toward the same spot rather than each unit's nearest approach.
## Falls back to message.position for non-structure targets (units, ground clicks).
func _resolve_movement_target(a_command: MoveCommand) -> Vector3:
	# A command may name its own destination outright — a Rearm flies to its runway's
	# final-approach fix, not to the airfield's origin — in which case nothing below applies.
	var named: Variant = a_command.movement_destination(owner)
	if named is Vector3:
		return named
	var target: Entity = a_command.message.target
	# TODO undo swapping or with and
	if target != null and is_instance_valid(target) and target is Entity \
			and target.is_in_group("fixture"):
		var map: Map = a_command.message.map
		if map != null:
			var cell: Vector2i = _resolve_structure_approach(a_command, target as Entity, map)
			if cell != Vector2i(-1, -1):
				return map.grid_to_world(cell)
	return a_command.message.position

## The footprint-adjacent cell `a_command` should walk to: the nearest one this unit's own
## class navmesh can actually path to, else the nearest one outright. Nearest-by-distance
## alone picked a pocket walled in by neighbouring buildings (a bot clusters them round its
## Compound): the agent stopped as close as its mesh allowed, re-resolved the same cell every
## tick, and a loaded Stock Truck sat there for good. Memoized per command — see
## _approach_command — and re-asked only if the chosen cell has since been built over.
func _resolve_structure_approach(a_command: MoveCommand, a_target: Entity, a_map: Map) -> Vector2i:
	if is_same(_approach_command, a_command) and _approach_cell != Vector2i(-1, -1) \
			and a_map.terrain_grid.is_passable(_approach_cell):
		return _approach_cell
	var nav_class: int = owner.movement.nav_agent_class if owner.movement != null \
			else SU.NO_NAV_CLASS
	var cells: Array[Vector2i] = SU.footprint_approach_cells(
		owner.global_position, a_target, a_map, nav_class)
	if cells.is_empty():
		return Vector2i(-1, -1)
	var chosen: Vector2i = cells.front()
	if owner.movement != null:
		var points: Array = cells.map(func(c: Vector2i) -> Vector3: return a_map.grid_to_world(c))
		var reachable: Variant = owner.movement.first_reachable(
			points, SU.class_standoff_reach(nav_class))
		if reachable != null:
			chosen = cells[points.find(reachable)]
	_approach_command = a_command
	_approach_cell = chosen
	return chosen

func update_commands(a_commands: Variant, a_add_to_queue: bool = false, a_prepend: bool = false) -> void:
	var queued_before: Array[MoveCommand] = _command_queue.duplicate()
	_update_commands(a_commands, a_add_to_queue, a_prepend)
	_release_dropped(queued_before)


## Drop everything waiting behind the active command and leave the active one running.
func clear_queue() -> void:
	var queued_before: Array[MoveCommand] = _command_queue.duplicate()
	_command_queue = []
	_release_dropped(queued_before)


func _update_commands(a_commands: Variant, a_add_to_queue: bool, a_prepend: bool) -> void:
	if a_commands == null:
		_command_queue = []
		_command = null
	elif a_commands is MoveCommand:
		# PREPEND is the interrupt: the new order takes over now and whatever was running goes to
		# the front of the queue, so the actor picks it back up when this one ends. Asked of
		# `a_prepend` ALONE — an interrupt issued without the additive modifier is not additive,
		# and gating this on both is what made "keep the queue" and "append" the same flag.
		if a_prepend:
			if _command != null:
				_command_queue.push_front(_command)
			_command = a_commands
		elif a_add_to_queue:
			_command_queue.append(a_commands)
		else:
			_command_queue = []
			_command = a_commands
	elif a_commands is Array and a_commands.size() > 0:
		if a_prepend:
			if _command != null:
				_command_queue.assign(a_commands.slice(1) + [_command] + _command_queue)
			else:
				_command_queue.assign(a_commands.slice(1) + _command_queue)
			_command = a_commands[0]
		elif a_add_to_queue and !a_prepend:
			_command_queue.append_array(a_commands)
		else:
			# Queue first, then the active command: the _command setter inspects the queue to
			# decide whether the outgoing command is leaving for good, so it must already show
			# the post-assignment state.
			_command_queue = a_commands.slice(1)
			_command = a_commands[0]
	else:
		push_error("MoveCommand argument is unsupported, arg=%s" % a_commands)
#endregion

#region Command processing
## One tick of the active order, reported to the owner's ActionTracker as what the tick was
## spent on. The five-step lifecycle is CLAUDE.md §Command system; what suspends it, why a
## fixed wing never stops when it acts, and how a dropped command is cleared are
## gdd/systems/commands/the-command-tick.md.
func _process_commands() -> void:
	owner.action_tracker.observe(_run_tick())


## The tick itself; returns what it was spent on — read from the branch the lifecycle took,
## so an animation can never disagree with what the command actually did.
func _run_tick() -> ActionTracker.Action:
	if _command_processing_suspended():
		_halt()
		return ActionTracker.Action.STUNNED if owner.is_stunned() else ActionTracker.Action.IDLE

	# A target that has left the world cannot be acted on, and holding the order sends the
	# actor to the map's centre — see _target_has_left_play.
	if _command != null and _target_has_left_play(_command.message):
		_drop_command()
		return ActionTracker.Action.IDLE

	var new_commands: Variant = _command.get_updated_state(owner) if _command != null else null

	if is_same(new_commands, null):
		_drop_command()
	elif not is_same(new_commands, _command):
		# The command reactively swapped itself for a different one. A swap spends no time,
		# so it keeps the action going — Build handing over to Assemble is still building.
		update_commands(new_commands, true, true)
		return owner.action_tracker.current_action()
	elif _command.can_act(owner):
		var action: ActionTracker.Action = _command.acting_action(owner)
		return action if _act_on_command() else ActionTracker.Action.IDLE
	elif owner.can_move() and _command.should_move(owner):
		_drive_movement()
		return ActionTracker.Action.MOVING
	return ActionTracker.Action.IDLE


## Whether a command's target has LEFT THE PLAY SPACE — it still exists, but no longer has a
## place in the world for anything standing in the world to act on.
##
## Garrisoning is the case: `Garrison.garrison()` removes the occupant from the scene tree
## outright, so nothing can acquire it — but a command issued BEFORE it boarded still holds
## the reference, and an off-tree node reports `global_position` (0, 0, 0). `CommandMessage.
## position` reads the target's position whenever a target is set, so the order silently
## becomes "go to the world origin". A stock truck that captures infantry by running them over
## did exactly that: it ran one down, took it aboard, and then set off for the middle of the
## map with a perfectly valid-looking order.
##
## This is the missing half of `_end_after_follow_target_died`, which is the same rule for a
## target that DIED — taken alive looks identical from the outside and is just as
## un-actionable. Death is deliberately NOT reported here: each command already handles a
## freed target, and a flying actor's orbit-on-death anchoring lives in that path.
##
## The target is read into a VARIANT before anything else touches it: a freed object fails a
## typed parameter's class check before the callee runs, and `freed == null` is true while
## `is_instance_valid(freed)` is false (CLAUDE.md §A freed object cannot be passed to a typed
## parameter).
static func _target_has_left_play(a_message: CommandMessage) -> bool:
	var target: Variant = a_message.target
	if target == null or not is_instance_valid(target):
		return false  # absent or dead — somebody else's branch
	var commandable: Commandable = target as Commandable
	return commandable != null and commandable.is_garrisoned()


## Whether this tick does nothing at all. Three states say so — stunned, still under
## construction, still under a canopy — and each KEEPS the orders rather than refusing them.
## Why each: gdd/systems/commands/the-command-tick.md §Three things suspend command
## processing.
func _command_processing_suspended() -> bool:
	return owner.is_stunned() or not owner.is_built \
		or (owner.movement != null and owner.movement.is_parachuting())


## Stop the owner where it stands. No-op for a commandable with no Movement (a structure).
func _halt() -> void:
	if owner.locomotion != null:
		owner.locomotion.stop()


## Clear a command that has ended — target died, left aggro range, or simply fulfilled.
##
## A FLYING unit anchors its orbit on the command's LAST-KNOWN destination BEFORE the
## command is cleared, so the circuit starts around where the action ended. A grounded one
## is fed an explicit zero rather than merely stopping to call set_velocity; why, and the
## open caveat: gdd/systems/commands/the-command-tick.md §A dropped command anchors.
func _drop_command() -> void:
	var last_goal: Variant = _last_goal_of(_command)
	_command = null
	if owner.locomotion != null:
		owner.locomotion.settle(last_goal)


## Where `a_command` was last aiming, or null when that is unknowable: no command, or a target
## that has left the world (garrisoned), whose position reads as the map origin — the trap
## _target_has_left_play exists for. Null lets a mover that cannot stop keep its circuit.
static func _last_goal_of(a_command: MoveCommand) -> Variant:
	if a_command == null:
		return null
	var target: Variant = a_command.message.target
	if target != null and is_instance_valid(target) and target is Node \
			and not (target as Node).is_inside_tree():
		return null
	return a_command.message.position


## In range and ready: perform the action, settle the movement it leaves behind, and take up
## whatever follow-up it returned. False when a stagger held the action back.
func _act_on_command() -> bool:
	# A hit that staggers the actor suppresses an action that opts into stagger, and holds
	# position until it wears off. Movement itself is never stagger-blocked, so a staggered
	# actor still reaches this point normally.
	if owner.is_staggered() and _command.blocked_by_stagger(owner):
		_halt()
		return false

	var acting_command: MoveCommand = _command
	var new_commands: Variant = _command.fulfill_action(owner)
	_settle_movement_after_acting(acting_command)

	if is_same(new_commands, null):
		_command = null
	elif new_commands != _command:
		_command = null
		update_commands(new_commands, true, true)
	return true


## What the actor does with its velocity now that it has acted — stop, keep flying at the
## target, or circle it. Why there are three answers rather than one:
## gdd/systems/commands/the-command-tick.md §A fixed wing does not stop when it acts.
func _settle_movement_after_acting(a_acting_command: MoveCommand) -> void:
	if owner.locomotion == null:
		return
	if owner.locomotion.can_hold_still():
		owner.locomotion.stop()
		return
	# Only for the command that just acted, and only while it is still the active one — a
	# fulfill_action that swapped the command has handed movement to somebody else.
	if not is_same(_command, a_acting_command) or _command == null:
		return
	if _command.should_move(owner):
		_drive_movement()
	else:
		owner.locomotion.settle(_command.message.position)


## Steer the owner toward its active command's destination for one tick. Split out of
## _process_commands so the ACT branch above can call it too: a fixed wing has to keep
## flying while it shoots (see Movement.can_hold_still).
func _drive_movement() -> void:
	if not _leave_pad_before_moving():
		return

	var followed: Commandable = _follow_target()
	if followed != null:
		# Remember the live relationship so we can spot the target's death next tick — a freed
		# reference reads as null, so it cannot be detected after the fact.
		_followed = followed
		_follow_cmd = _command
	else:
		# Not following, or no longer. `_follow_cmd` (a RefCounted we hold) is the reliable
		# "we WERE following" flag; `_followed` reads as null once freed, so it cannot gate this.
		var target_died: bool = _follow_cmd != null and is_same(_follow_cmd, _command) \
				and not is_instance_valid(_followed)
		_followed = null
		_follow_cmd = null
		if target_died:
			_end_after_follow_target_died()
			return

	# Following, locomotion HOLDS once its body touches the target's; the command is KEPT so
	# the follower resumes if the target moves off.
	owner.locomotion.set_goal(_resolve_movement_target(_command), _arrival_for(_command), followed)
	if owner.locomotion.tick() == Locomotion.Progress.ARRIVED:
		_arrive(followed)


## Stop at the goal only on the FINAL queued destination, and never for an attack or a patrol,
## which carry on past the point they aim at.
func _arrival_for(a_command: MoveCommand) -> Locomotion.Arrival:
	var is_final: bool = _command_queue.is_empty() \
			and not (a_command is Attack) and not (a_command is Patrol)
	return Locomotion.Arrival.STOP if is_final else Locomotion.Arrival.PASS_THROUGH


## Bring a parked aircraft off its pad, and report whether the caller may go on to move it.
##
## Movement.set_velocity is suppressed outright while GROUNDED_TEMP, so without this a
## docked unit would sit on the deck ignoring a perfectly good order. FALSE means STILL ON
## THE PAD — the runway was busy and it is waiting its turn. The caller must stop there:
## `is_navigation_finished()` reports true for anything GROUNDED_TEMP, so the arrival branch
## would read a unit that has not moved an inch as having reached its destination and throw
## its order away. Ordering four aircraft off one strip lost three of them exactly that way.
func _leave_pad_before_moving() -> bool:
	var docking: Docking = owner.docking
	if docking == null or not docking.is_docked_on_pad():
		return true
	docking.leave_dock()
	return not docking.is_docked_on_pad()


## End a follow whose target has died, rather than driving at the origin — `message.position`
## falls back to world_position (0, 0, 0) once the target is gone. A FLYING unit orbits the
## last place it saw the target instead of stopping, because it cannot stop.
##
## message.position holds the last-updated target position from before the target was freed,
## which is where a mover that cannot stop circles.
func _end_after_follow_target_died() -> void:
	var last_seen: Vector3 = _command.message.position
	_command = null
	owner.locomotion.settle(last_seen)


## The path has finished — chain to the next waypoint, or settle here.
func _arrive(a_followed: Commandable) -> void:
	# HOVERING/FLYING pass-through: with more waypoints after this one, load the next
	# destination on the SAME tick rather than nulling the command and restarting on the next.
	# That one-tick standstill is what would otherwise break the banking curve.
	if owner.aerial != null and not _command_queue.is_empty() and a_followed == null:
		_chain_to_next_waypoint()
		return

	owner.locomotion.arrive()
	# A follow keeps its command on arrival; a plain move ends. So does anything else whose
	# whole purpose was to get here — but NOT a command that travels in order to act in range.
	# Dropping one of those is how a builder that had to WALK to its site silently lost its
	# order, and how an aircraft flying to a Rearm approach fix was left circling with no order
	# at all. See MoveCommand.ends_on_arrival and CLAUDE.md §Command system.
	if a_followed == null and _command.ends_on_arrival():
		_command = null


## Pop the next queued waypoint and set off for it within this same tick.
func _chain_to_next_waypoint() -> void:
	_command = _command_queue.pop_front()
	load_destination(_command)
	owner.locomotion.tick()


func _update_state() -> void:
	if _command == null and not _command_queue.is_empty():
		_command = _command_queue.pop_front()

	# Delegate to the owner's command processor (Commandable._process_commands),
	# which routes structure-flavored commands (Train → Production.enqueue,
	# base MoveCommand → Commandable.set_rally) before falling back to this
	# receiver's default handling via _process_commands(). Calling our own
	# _process_commands() here would bypass that routing entirely, which is why
	# structure training and rally points silently did nothing.
	owner._process_commands()

	_reconcile_follow_avoidance()
#endregion

#region Private helpers
## The friendly unit this unit is currently "following" — i.e. its active command
## moves it toward another unit on its own team — or null. Used both to suppress
## reciprocal avoidance and to stop at the followed unit's body.
func _follow_target() -> Commandable:
	if _command == null or not _command.should_move(owner):
		return null
	var t: Entity = _command.message.target
	# TODO remove the hacky check
	if t != null and is_instance_valid(t) and t is Commandable \
				and t != owner and t.is_in_group("unit") \
			and (t as Commandable).commander_id == owner.commander_id:
		return t as Commandable
	return null

## Suppress reciprocal RVO avoidance between this unit and the one it follows so
## the follower can close in without the pair shoving each other apart. Recomputed
## every tick, so it clears when the command changes, the target dies, or idle.
func _reconcile_follow_avoidance() -> void:
	if owner.movement == null:
		return
	owner.movement.set_avoidance_follow_target(_avoidance_exception_target())

## The one commandable this unit ignores in RVO this tick: whatever its active command names
## (a garrison order names the other half of itself — see MoveCommand.avoidance_exception),
## otherwise the friendly unit it is following.
##
## One partner, because that is what Movement.set_avoidance_follow_target holds. The
## command's answer wins: an order that exists in order to close with another unit knows more
## about the pair than the generic follow rule, which asks a narrower question (same
## commander, group "unit", still moving) and would drop the exemption at the worst moment.
func _avoidance_exception_target() -> Commandable:
	var declared: Commandable = _command.avoidance_exception(owner) if _command != null else null
	return declared if declared != null else _follow_target()
#endregion
