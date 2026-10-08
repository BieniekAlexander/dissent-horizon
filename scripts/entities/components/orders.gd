class_name Orders
extends Node

## The ORDER-TAKING half of an Actor: its command queue (CommandReceiver), the rally queue a
## stationary producer hands to what it makes, what an incoming order is admitted as, and the
## per-tick command processing. A component a doc omits with `commandable: false` — a piece that
## can be damaged but never ordered (the Recon Drone) carries none, and every order to it is a
## no-op. gdd/systems/authoring/composition-rework.md §Commandability is a capability.
##
## Actor keeps its order methods (`update_commands`, `current_command`, …) as forwards to this
## component, and drives `tick` from its own physics tick, so the order within a tick is
## unchanged.

## The command queue. Created with the component, initialised against the host in _ready.
var receiver: CommandReceiver = CommandReceiver.new()

## PRE-ISSUED command queue for a stationary can_rally() actor (no locomotion): the orders every
## unit it produces or releases inherits, in order, as though the player had given them to that
## unit the moment it appeared. Fed by intercepting bare MoveCommands in update_commands (see
## _absorb_rally_commands) — a plain right-click REPLACES the queue, a shift right-click APPENDS.
##
## These are TEMPLATES, never handed out directly: rally_chain() returns fresh copies, so two
## units produced from one rally can't share command instances. Meaningless for a mobile actor,
## which shares its own active movement instead — see rally_chain.
var rally_commands: Array[MoveCommand] = []

## The target a TURRET keeps shooting while the host carries out a movement order: the Attack's
## target when a replacing move took over from it. Held until it leaves range or sight, dies, the
## host holds fire, or another Attack or a Stop replaces it. UNTYPED: it may be freed.
## gdd/systems/combat/turrets.md §Attacking while moving.
var held_attack_target: Variant = null


func host() -> Actor:
	return get_parent() as Actor


## `a_node`'s Orders component, or null — an Actor that takes no orders, or anything else.
static func of(a_node: Variant) -> Orders:
	if a_node == null or not is_instance_valid(a_node) or not (a_node is Node):
		return null
	return (a_node as Node).get_node_or_null("Orders") as Orders


func _ready() -> void:
	receiver.initialize(host())


func _notification(a_what: int) -> void:
	if a_what == NOTIFICATION_PREDELETE:
		# Drop the command chain while the host is still fully valid. Each MoveCommand's
		# PREDELETE resets the host's Movement.speed_cap (group-move cleanup), so it must run
		# before the host's destructor frees Movement — otherwise it dereferences a half-freed
		# actor and hard-crashes. See MoveCommand._notification.
		receiver.update_commands(null)
		rally_commands.clear()


#region Commands
func current() -> MoveCommand:
	return receiver._command


func chain() -> Array[MoveCommand]:
	return receiver.get_command_chain()


func load_destination(a_command: MoveCommand) -> void:
	receiver.load_destination(a_command)


## Give the host `a_commands` — one order or a list — replacing what it is doing, or appended
## (`a_add_to_queue`), or ahead of it (`a_prepend`, an interrupt). What an order is admitted as
## depends on the host's other components: a stationary producer absorbs a bare move as a rally
## point, a Deployable and a Sortie may reshape the list, an order to shoot lifts hold fire, and
## a grounded aircraft takes off for an order that needs it to move.
func update_commands(
	a_commands: Variant, a_add_to_queue: bool = false, a_prepend: bool = false
) -> void:
	var actor: Actor = host()
	# Absorbed HERE, at the point of issue, because this is where the additive flag still exists.
	if _absorb_rally_commands(a_commands, a_add_to_queue):
		return
	if actor.deployable != null and a_commands != null:
		var admission: Dictionary = actor.deployable.admit(
			Actor._as_orders(a_commands), a_add_to_queue, receiver.get_command_chain()
		)
		var admitted: Array[MoveCommand] = admission["orders"]
		if admission["keep_active"]:
			receiver.clear_queue()
		if admitted.is_empty():
			return
		a_commands = admitted
		a_add_to_queue = admission["add_to_queue"]
		# Nothing jumps ahead of a transition: an interrupt waits behind it like any order.
		a_prepend = a_prepend and not actor.deployable.is_transitioning()
	var sortie: Sortie = Sortie.of(actor)
	if sortie != null and a_commands != null:
		var admitted_by_sortie: Array[MoveCommand] = sortie.admit(Actor._as_orders(a_commands))
		if admitted_by_sortie.is_empty():
			return
		a_commands = admitted_by_sortie
	_release_hold_fire_for(a_commands)
	_hold_attack_target_through(a_commands, a_add_to_queue)
	if not a_add_to_queue:
		_reorient_host_for(a_commands)
	receiver.update_commands(a_commands, a_add_to_queue, a_prepend)


## Keep the current Attack's target as the held one when a replacing order that is not itself an
## attack takes over, so a turret goes on shooting it on the move. A new Attack, or a Stop, drops
## it: the first names its own target, the second means cease.
func _hold_attack_target_through(a_commands: Variant, a_add_to_queue: bool) -> void:
	var incoming: Array[MoveCommand] = Actor._as_orders(a_commands)
	if incoming.any(func(c: MoveCommand) -> bool: return c is Attack or c is Stop):
		held_attack_target = null
		return
	if a_add_to_queue or incoming.is_empty():
		return
	var attack := current() as Attack
	if attack == null or not is_instance_valid(attack.message.target):
		return
	var weapon: Weapon = (
		host().weapon_inventory.weapon_for_target(attack.message.target)
		if host().weapon_inventory != null
		else null
	)
	if weapon != null and weapon.turret:
		held_attack_target = attack.message.target


## An order that means "shoot" releases hold fire on receipt — queued or not — so a held unit
## told to attack will also pick up targets on its own again afterwards.
func _release_hold_fire_for(a_commands: Variant) -> void:
	for command: Variant in a_commands if a_commands is Array else [a_commands]:
		if command is MoveCommand and (command as MoveCommand).releases_hold_fire():
			host().is_holding_fire = false
			return


## A REPLACING order changes the host's course: a garrison host tells the units walking to it,
## and a grounded aircraft lifts off for an order that needs it to move. Commands that handle
## their own landing (Evacuate) return false from should_move and trigger no take-off.
##
## Both aerial modes, not just HOVERING: a FLYING unit docks too, and one re-ordered off a pad
## without this would carry the order out by taxiing along the deck.
func _reorient_host_for(a_commands: Variant) -> void:
	var actor: Actor = host()
	if actor.garrison != null and not actor.garrison._pending_garrison_units.is_empty():
		actor.garrison.cancel_pending_garrison()
	if actor.aerial == null:
		return
	var first_cmd: MoveCommand = null
	if a_commands is MoveCommand:
		first_cmd = a_commands
	elif a_commands is Array and not (a_commands as Array).is_empty():
		first_cmd = (a_commands as Array)[0]
	if actor.aerial.is_grounded_temp():
		if first_cmd != null and first_cmd.should_move(actor):
			# A unit on a DOCKING PAD leaves through leave_dock, which gives the pad back and taxis
			# it out to a runway threshold before it climbs; taking off in place would skip the
			# roll-out the runways exist for.
			if actor.docking != null and actor.docking.is_docked_on_pad():
				actor.docking.leave_dock()
			else:
				actor.aerial.take_off_for_movement()
	elif actor.aerial.is_pending_land():
		actor.aerial.cancel_pending_land()


## Route the current command: a structure turns a Train into a purchase on the commander's
## production queue; everything else goes to the receiver's default handling. (Bare moves
## aimed at a stationary producer never get this far — update_commands absorbs them.)
func process() -> void:
	var actor: Actor = host()
	var command: MoveCommand = current()
	if command != null and actor.production != null and command is Train:
		# Training is a PURCHASE, so it goes through the commander's global production queue
		# instead of being enqueued here — the queue deducts the cost and hands the job back to
		# this producer once the energy exists, so an unaffordable order waits rather than being
		# dropped. This is the single-producer entry point (scenario events, the bot); the
		# player's multi-select train submits one purchase across the whole selection
		# (OrderDispatcher). No is_built gate: a structure under construction accepts orders,
		# and the queue holds them until it finishes (ProductionQueue._dispatch).
		if actor.commander != null and actor.commander.can_order(command.message.tool.type):
			actor.commander.production_queue.submit_train(command.message.tool, [actor])
		update_commands(null)
		return
	receiver._process_commands()


## The command half of the host's tick: pick up a target while idle, run the queue, and bring a
## hovering garrison host down to its waiting passengers once it has nothing else to do.
func tick() -> void:
	var actor: Actor = host()
	# Aggro pickup is gated on being FINISHED as well as idle: the receiver refuses to act on an
	# unbuilt owner's commands, so an ungated pickup would latch onto a target it cannot shoot.
	# A grounded aircraft picks up nothing (can_use_weapons), nor does a piece holding fire
	# (get_aggro_near_position answers null).
	if actor.is_built and receiver.is_idle() and actor.can_use_weapons():
		var aggro_cmd: MoveCommand = actor.get_aggro_near_position()
		if aggro_cmd != null:
			update_commands(aggro_cmd)
	receiver._update_state()
	if not actor.is_inside_tree():
		return
	_tick_held_attack_target()
	# A HOVERING garrison host with pending units descends to accept them once idle — both when
	# already idle at the moment intent is registered and when a movement command completes.
	if (
		actor.garrison != null
		and not actor.garrison._pending_garrison_units.is_empty()
		and actor.aerial != null
		and actor.aerial.mode == Movement.Mode.HOVERING
		and receiver.is_idle()
	):
		actor.aerial.land(Callable())


## Shoot the held target this tick if a turret can: aim at it, and fire once it is aimed, loaded
## and locked on — the rules an Attack's turret fire follows. Drop it once it can no longer be
## shot at all. Nothing to do while an Attack is running: the Attack aims for itself.
func _tick_held_attack_target() -> void:
	if held_attack_target == null or current() is Attack:
		return
	var actor: Actor = host()
	var target: Variant = held_attack_target
	if (
		not is_instance_valid(target)
		or not (target as Node).is_inside_tree()
		or actor.is_holding_fire
		or not (target as Entity).is_visible_to(actor.commander_id)
	):
		held_attack_target = null
		return
	var weapon: Weapon = (
		actor.weapon_inventory.weapon_for_target(target) if actor.weapon_inventory != null else null
	)
	if weapon == null or not weapon.turret or not SU.is_in_attack_range(weapon, actor, target):
		held_attack_target = null
		return
	var aim: Vector3 = (target as Entity).global_position
	weapon.aim_turret_toward(actor, aim)
	if not actor.can_use_weapons() or not weapon.is_turret_aimed_at(actor, aim):
		return
	weapon.hold_target(target)
	if weapon.is_ready() and weapon.is_locked_on(target):
		weapon.fire(actor, target)


#endregion


#region Rally
func set_rally(a_command: MoveCommand) -> void:
	rally_commands = [a_command]


func append_rally(a_command: MoveCommand) -> void:
	rally_commands.append(a_command)


func clear_rally() -> void:
	rally_commands.clear()


## The command chain a unit produced or released by the host should inherit, as FRESH copies it
## owns outright (MoveCommand.duplicated); empty for "no forced destination". A mobile host has
## no pre-issued queue and hands on its own active movement instead — so a transport destroyed
## mid-move passes its heading to its evacuated passengers — excluding commands that are not
## motion (should_move() false, e.g. Evacuate itself).
func rally_chain() -> Array[MoveCommand]:
	var out: Array[MoveCommand] = []
	if not host().can_move():
		for command: MoveCommand in rally_commands:
			out.append(command.duplicated())
		return out
	var command: MoveCommand = current()
	if command != null and command.should_move(host()):
		out.append(command.duplicated())
	return out


## The first pre-issued command, or null — the heading readers use to bias where a unit appears
## (Production's spawn offset, Garrison's exit-side seed). The live template, NOT a copy:
## callers only read `message.position` off it; rally_chain() is what hands orders out.
func rally_destination() -> MoveCommand:
	if not host().can_move():
		return rally_commands[0] if not rally_commands.is_empty() else null
	var command: MoveCommand = current()
	if command != null and command.should_move(host()):
		return command
	return null


## Route a bare MoveCommand aimed at a stationary can_rally() host into its pre-issued queue
## instead of its receiver — a structure can't walk anywhere, so a move order on it means "send
## what you make there". True when the commands were absorbed and must not reach the receiver.
##
## Only EXACT MoveCommands are absorbed — an Attack or Evacuate aimed at a structure is a real
## order for the structure itself — and a mixed array is left alone rather than split, so the
## receiver still sees a coherent chain.
func _absorb_rally_commands(a_commands: Variant, a_add_to_queue: bool) -> bool:
	var actor: Actor = host()
	if actor.can_move() or not actor.can_rally() or a_commands == null:
		return false
	var incoming: Array[MoveCommand] = []
	if a_commands is MoveCommand:
		incoming.append(a_commands)
	elif a_commands is Array:
		for command: Variant in a_commands:
			if not (command is MoveCommand):
				return false
			incoming.append(command)
	else:
		return false
	if incoming.is_empty():
		return false
	for command: MoveCommand in incoming:
		if command.get_script() != MoveCommand:
			return false
	if not a_add_to_queue:
		rally_commands.clear()
	rally_commands.append_array(incoming)
	return true
#endregion
