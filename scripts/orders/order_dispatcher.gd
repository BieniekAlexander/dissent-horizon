class_name OrderDispatcher
extends RefCounted

## Applies a player's order to the simulation: the non-UI half of issuing a command, moved out
## of RTSController so a recorded order replays through the same code that ran it live.
## gdd/systems/commands/recording-and-replay.md §The order stream.
##
## Everything here reads the order, never the input device: the modifiers held when it was
## given (`queue`, `narrow`, `broaden`, `standing`, `line`) arrive as data. The controller asks
## the same rules for its previews (recipients, narrowed, line_destinations), so what it shows
## and what is applied cannot disagree.

## Floor on the radius a group order scatters destinations within, so a small group still fans
## out enough to stop units stacking on one point.
const MIN_FAN_OUT_RADIUS: float = 5.0
## Scatter radius contributed per unit, as a multiple of the group's body radius.
const FAN_OUT_RADIUS_PER_UNIT: float = 2.5
## How many units one `modifier_broaden` press of a train button buys. Five is the RTS
## convention for a batch key and is short enough that a mis-press is cheap to cancel.
const BULK_PURCHASE_COUNT: int = 5


#region Orders
## Apply `a_order`, its pieces resolved in `a_scenario`. Returns what the giver's interface acts
## on afterwards: for a COMMAND or PENDING_COMMAND the messages that want a waypoint indicator,
## for a DROP the pieces it landed; empty for anything else.
static func apply(order: PlayerOrder, scenario: Scenario) -> Array:
	var none: Array = []
	match order.kind:
		PlayerOrder.Kind.COMMAND:
			var command_type: Script = order.command_type()
			if command_type == null:
				push_error("order names no command script: %s" % order.data.get("command"))
				return none
			var commander: Commander = _commander(scenario, order.commander_id)
			var message: CommandMessage = PlayerOrder.message_from_dict(
				order.data.get("message", {}), scenario.map, scenario, commander
			)
			var actors: Array = PlayerOrder.pieces_of(order.data.get("actors", []), scenario)
			# Only the debug view lets a player order another commander's pieces, and that is no
			# order a player can give (recording-and-replay.md §Debug mode).
			if actors.any(func(a: Entity) -> bool: return a.commander_id != order.commander_id):
				scenario.note_debug_change("ordered another commander's piece")
			return apply_command(scenario.map, command_type, actors, message, order.data)
		PlayerOrder.Kind.HOLD_FIRE:
			hold_fire(
				PlayerOrder.pieces_of(order.data.get("actors", []), scenario),
				bool(order.data.get("queue", false)),
				scenario.map
			)
		PlayerOrder.Kind.AUTOCAST:
			var commander: Commander = _commander(scenario, order.commander_id)
			if commander != null:
				commander.toggle_autocast(StringName(str(order.data.get("ability", ""))))
		PlayerOrder.Kind.CANCEL_PURCHASE:
			var owner: Commander = _commander(scenario, int(order.data.get("owner", -1)))
			if owner != null and owner.production_queue != null:
				for id: Variant in order.data.get("purchases", []):
					var transaction: PurchaseTransaction = owner.production_queue.find_by_id(
						int(id)
					)
					if transaction != null:
						owner.production_queue.cancel(transaction)
		PlayerOrder.Kind.CANCEL_JOB:
			var producer := (
				scenario.piece_by_serial(int(order.data.get("producer", 0))) as Commandable
			)
			if producer != null and producer.production != null:
				producer.production.cancel(int(order.data.get("job", -1)))
		PlayerOrder.Kind.RELEASE_OCCUPANT:
			release_occupant(
				scenario.piece_by_serial(int(order.data.get("host", 0))) as Commandable,
				scenario.piece_by_serial(int(order.data.get("occupant", 0))) as Commandable
			)
		PlayerOrder.Kind.UNLOCK_SANCTION:
			var commander: Commander = _commander(scenario, order.commander_id)
			if commander != null and commander.sanction_grid != null:
				var entry: SanctionGrid.Entry = commander.sanction_grid.cell(
					int(order.data.get("tier", -1)), int(order.data.get("column", -1))
				)
				if entry != null:
					commander.sanction_grid.try_unlock(entry)
		PlayerOrder.Kind.DROP:
			var commander: Commander = _commander(scenario, order.commander_id)
			if commander != null and commander.deployment != null:
				var aim: Array = order.data.get("aim", [0.0, 0.0])
				return commander.deployment.drop(
					int(order.data.get("drop", 0)), Vector2(float(aim[0]), float(aim[1]))
				)
		PlayerOrder.Kind.PENDING_COMMAND:
			var command_type: Script = order.command_type()
			var owner: Commander = _commander(scenario, int(order.data.get("owner", -1)))
			if command_type == null or owner == null or owner.production_queue == null:
				return none
			var message: CommandMessage = PlayerOrder.message_from_dict(
				order.data.get("message", {}), scenario.map, scenario, owner
			)
			var purchases: Array = []
			for id: Variant in order.data.get("purchases", []):
				var transaction: PurchaseTransaction = owner.production_queue.find_by_id(int(id))
				if transaction != null:
					purchases.append(transaction)
			return apply_pending_command(
				scenario.map, command_type, purchases, message, bool(order.data.get("queue", false))
			)
		PlayerOrder.Kind.DIALOG:
			var manager: ScenarioTriggerManager = scenario.trigger_manager()
			var dialog: ScenarioDialog = (
				manager.dialog_by_serial(int(order.data.get("dialog", 0)))
				if manager != null
				else null
			)
			if dialog != null:
				if bool(order.data.get("secondary", false)):
					dialog.choose_secondary()
				else:
					dialog.acknowledge()
	return none


## Let `a_occupant` out of `a_host`'s garrison, when it is one of the host's own side
## (Garrison.can_release_occupant) — never a captive.
static func release_occupant(host: Commandable, occupant: Commandable) -> void:
	if host == null or occupant == null:
		return
	var garrison: Garrison = host.get_node_or_null("Garrison") as Garrison
	if garrison != null and garrison.can_release_occupant(occupant):
		garrison.evacuate_one(occupant, host.map)


## Store a command on each of `a_purchases` for the unit it will produce: one command instance
## and one deep-copied message per purchase, as live orders get, since two units sharing a
## command trade destinations through it. Additive appends; otherwise it replaces what was
## stored. Returns the messages that want a waypoint indicator — one per purchase that took it.
static func apply_pending_command(
	map: Map, command_type: Script, purchases: Array, message: CommandMessage, add_to_queue: bool
) -> Array[CommandMessage]:
	var indicated: Array[CommandMessage] = []
	for transaction: PurchaseTransaction in purchases:
		var snapshot: CommandMessage = CommandMessage.deep_copy(message)
		if map != null:
			snapshot.world_position.y = map.terrain_height_at(snapshot.xz_position)
		if transaction.queue_player_command(command_type.new(snapshot), not add_to_queue):
			indicated.append(snapshot)
	return indicated


static func _commander(scenario: Scenario, commander_id: int) -> Commander:
	if commander_id < 0 or commander_id >= scenario.commanders.size():
		return null
	return scenario.commanders[commander_id] as Commander


## Toggle hold fire across `a_actors` as one: they all hold unless every one already does.
## Only an actor whose card offers hold fire is touched.
static func toggle_hold_fire(actors: Array) -> void:
	hold_fire(actors, false, null)


## The hold-fire toggle: at once, or — with the additive modifier (`a_is_queued`) — as a step at
## the end of each actor's queue that sets the same value when the queue reaches it. The value is
## what the toggle means NOW, as the button showed it when pressed.
static func hold_fire(actors: Array, is_queued: bool, map: Map) -> void:
	var is_holding: bool = not CommandButtonState.all_hold_fire(actors)
	for node: Variant in actors:
		var actor := node as Commandable if is_instance_valid(node) else null
		if (
			actor == null
			or not CommandContextParser.commands_for(actor).has(
				CommandContextParser.HOLD_FIRE_COMMAND
			)
		):
			continue
		if is_queued:
			actor.update_commands(SetHoldFire.new(CommandMessage.new(map), is_holding), true)
		else:
			actor.is_holding_fire = is_holding


#endregion


#region Commands
## Which of `a_actors` take an order for `a_command_type`: the capable ones, narrowed to one when
## the arity says so, only movers for a line, one host for an Embark. Empty when none can.
static func recipients(
	command_type: Script, actors: Array, message: CommandMessage, modifiers: Dictionary
) -> Array:
	var capable: Array = actors.filter(
		func(c: Variant) -> bool:
			return (
				is_instance_valid(c)
				and c is Commandable
				and (
					command_type.meets_precondition(c, message)
					== MoveCommand.PreconditionFailureCause.NONE
				)
			)
	)
	if capable.is_empty():
		return capable
	# Narrowing runs on the CAPABLE set, not the raw selection: "assign to one actor" means
	# one actor that can actually carry the order out, so a narrowed build with a soldier
	# nearest the site still goes to a builder.
	capable = narrowed(
		command_type,
		capable,
		message,
		arity_of(command_type, message, modifiers),
		not bool(modifiers.get("broaden", false))
	)
	# A line order is only for what can stand on a line. An immobile actor is not given the
	# order, rather than being handed the middle of the line as a rally point.
	if not (modifiers.get("line", []) as Array).is_empty():
		capable = line_movers(capable)
	# An EMBARK is collected by ONE host — the nearest applicable one — so everything else
	# selected falls through to the bystander move rather than a second transport racing for
	# the same passenger.
	if command_type == Embark and not capable.is_empty():
		capable = Embark.nearest_host(capable, message)
	return capable


## Issue `a_command_type` to `a_actors` — the whole selection — as one order. Returns the
## per-actor messages that want a waypoint indicator.
static func apply_command(
	map: Map, command_type: Script, actors: Array, message: CommandMessage, modifiers: Dictionary
) -> Array[CommandMessage]:
	var indicated: Array[CommandMessage] = []
	var capable: Array = recipients(command_type, actors, message, modifiers)
	if capable.is_empty():
		return indicated
	var add_to_queue: bool = bool(modifiers.get("queue", false))

	# Training is a PURCHASE, not a per-unit command: one order buys ONE unit (or a batch, under
	# broaden), and the capable producers are handed to the transaction as candidates; the
	# commander's queue sends it to whichever is free first. No Train command reaches a structure.
	if command_type == Train:
		_purchase_training(capable, message, modifiers)
		return indicated

	# A build order is ONE purchase and ONE blueprint however many builders were selected:
	# made here, before the per-unit snapshots, so every builder's snapshot shares them
	# (CommandMessage.deep_copy passes the references through).
	if command_type == Build:
		var payer: Commander = (capable[0] as Entity).commander
		Build.submit_purchase(payer, message)
		Build.plan_structure(payer, message)

	# Any multi-unit command caps every mobile unit's speed to the slowest one's, so a
	# mixed-speed group doesn't stretch out over the trip. Reset when each unit's command is
	# destroyed (MoveCommand._notification / CommandReceiver._process_commands).
	var slowest: float = slowest_group_speed(capable)
	var apply_speed_cap: bool = slowest >= 0.0
	if apply_speed_cap:
		message.match_group_speed = true

	var line: Array = modifiers.get("line", [])
	var unit_to_destination: Dictionary = (
		line_destinations(capable, _line_point(line, 0), _line_point(line, 2))
		if not line.is_empty()
		else fanned_destinations(map, command_type, capable, message)
	)

	# For a Defend order, ONE region collider — a hard copy of the group's widest aggro shape,
	# pinned at the post — that every defender scans against. A copy, because a borrowed live
	# shape would drag the region around with its owner. Leased to the issued messages, and
	# freed when the last is released (lease_region_shape).
	var defend_shape: CollisionShape3D = null
	if command_type == Defend:
		var center: Vector3 = message.world_position
		center.y = map.terrain_height_at(message.xz_position)
		defend_shape = make_defend_region_shape(map, largest_aggro_shape(capable), center)

	# Identity token for THIS order, and nothing else — none of its fields are ever read. Every
	# per-unit snapshot points at it so MoveCommand's destination-swap check can recognise true
	# siblings via is_same(). Fresh per order, or separate orders become indistinguishable.
	var batch_origin: CommandMessage = CommandMessage.new(map)
	var interrupts: bool = command_type.is_interrupt() and not add_to_queue
	var defend_messages: Array[CommandMessage] = []
	for c: Commandable in capable:
		var snapshot := CommandMessage.deep_copy(message)
		snapshot.origin = batch_origin
		if defend_shape != null:
			snapshot.aggro_shape = defend_shape
		if command_type == Attack:
			snapshot.persist = true
		if unit_to_destination.has(c):
			snapshot.world_position = VU.from_xz(unit_to_destination[c])
		snapshot.world_position.y = map.terrain_height_at(snapshot.xz_position)
		if command_type.requires_position():
			indicated.append(snapshot)
		var new_cmd: MoveCommand = (
			Patrol.for_actor(c, snapshot) if command_type == Patrol else command_type.new(snapshot)
		)
		# Sequencing is a fact about WHEN this order was handed out, so it is stamped here,
		# once per recipient (Commander.next_task_sequence).
		if new_cmd is TaskShelter and c.commander != null:
			(new_cmd as TaskShelter).sequence = c.commander.next_task_sequence()
		# An INTERRUPT keeps the actor's queue, taking over now and pushing whatever was
		# running to the front (MoveCommand.is_interrupt) — unless the order is additive.
		c.update_commands(new_cmd, add_to_queue, interrupts)
		# AFTER the handover: update_commands drops the outgoing command, whose PREDELETE
		# resets speed_cap, so capping first would be wiped microseconds later.
		if apply_speed_cap and c.movement != null:
			c.movement.speed_cap = slowest
		if defend_shape != null:
			defend_messages.append(snapshot)
	if defend_shape != null:
		lease_region_shape(defend_shape, defend_messages)

	# Members of the selection that did NOT receive this order still go where it points, for a
	# command that asks for it (MoveCommand.bystanders_move) or whenever broaden was held.
	# AFTER the main loop, so the recipients are settled before anyone is judged a bystander.
	# gdd/systems/commands/the-click-ladder.md §What the members that do NOT receive it do.
	if command_type.bystanders_move() or bool(modifiers.get("broaden", false)):
		order_bystanders_to_move(map, actors, capable, message, add_to_queue)
	return indicated


## Submit a training purchase for `a_capable`'s owner. BROADEN BUYS A BATCH; re-checking the
## precondition between submissions is what makes it "as many as you can afford" — each
## transaction reserves its energy as it lands — and with the additive modifier the check never
## fails, so the batch lands whole and is requisitioned in order.
static func _purchase_training(
	capable: Array, message: CommandMessage, modifiers: Dictionary
) -> void:
	# The purchase is the PRODUCERS' owner's: the player's own except when debug lets them
	# order another commander's pieces.
	var commander: Commander = (capable[0] as Entity).commander
	if commander == null:
		return
	var producers: Array = capable.filter(func(c: Entity) -> bool: return c.commander == commander)
	var count: int = BULK_PURCHASE_COUNT if bool(modifiers.get("broaden", false)) else 1
	for i: int in count:
		if (
			i > 0
			and (
				Train.meets_precondition(producers[0] as Commandable, message)
				!= MoveCommand.PreconditionFailureCause.NONE
			)
		):
			break
		commander.production_queue.submit_train(
			message.tool, producers, bool(modifiers.get("standing", false))
		)


static func _line_point(line: Array, index: int) -> Vector2:
	return Vector2(float(line[index]), float(line[index + 1]))


## The arity an order goes out at: NARROW first (so holding both still narrows), then broaden,
## else the command's own default. gdd/systems/ux/ui/control-matrices.md §Cast arity.
static func arity_of(
	command_type: Script, message: CommandMessage, modifiers: Dictionary
) -> MoveCommand.CastArity:
	if command_type == null:
		return MoveCommand.CastArity.ALL
	return modified_arity(
		command_type.default_cast_arity(message),
		bool(modifiers.get("narrow", false)),
		bool(modifiers.get("broaden", false))
	)


## Apply the modifiers to a default arity — the ONE statement of the rule.
static func modified_arity(
	default_arity: MoveCommand.CastArity, is_narrow: bool, is_broaden: bool
) -> MoveCommand.CastArity:
	if is_narrow:
		return MoveCommand.CastArity.SINGLE
	if is_broaden:
		return MoveCommand.CastArity.ALL
	return default_arity


## `a_actors` narrowed to the one that takes a SINGLE-arity order: the nearest free one, idle
## first unless `a_prefer_idle` is off. Train is exempt — a purchase has one actor already.
## gdd/systems/ux/ui/selection-and-input.md §The narrow modifier picks the nearest IDLE actor.
static func narrowed(
	command_type: Script,
	actors: Array,
	message: CommandMessage,
	arity: MoveCommand.CastArity,
	prefer_idle: bool
) -> Array:
	if actors.size() <= 1 or command_type == Train or arity == MoveCommand.CastArity.ALL:
		return actors
	var candidates: Array = []
	for node: Node in actors:
		var actor := node as Commandable
		if actor == null:
			continue
		candidates.append([VU.in_xz(actor.global_position), command_type.is_free_to_take(actor)])
	var index: int = narrowed_index(candidates, message.xz_position, prefer_idle)
	return [actors[index]] if index >= 0 else actors


## Which of `a_candidates` — each `[xz_position: Vector2, is_idle: bool]` — takes a narrowed
## order aimed at `a_target`; -1 for an empty set. An idle candidate outranks a busy one however
## far away it is; among equals, distance decides. Node-free so the rule can be pinned alone.
static func narrowed_index(candidates: Array, target: Vector2, prefer_idle: bool) -> int:
	var best: int = -1
	var best_distance: float = INF
	var best_is_idle: bool = false
	for i: int in candidates.size():
		var idle: bool = prefer_idle and candidates[i][1] as bool
		var distance: float = (candidates[i][0] as Vector2).distance_to(target)
		if (
			best == -1
			or (idle and not best_is_idle)
			or (idle == best_is_idle and distance < best_distance)
		):
			best = i
			best_distance = distance
			best_is_idle = idle
	return best


static func line_movers(actors: Array) -> Array:
	return actors.filter(
		func(c: Node) -> bool:
			return is_instance_valid(c) and c is Commandable and (c as Commandable).can_move()
	)


## Each actor mapped to its own standing point on the line `a_start`–`a_end`. Ground units and
## aircraft are laid out SEPARATELY, each as if it were the only group on the line, so a mixed
## selection fills the line twice rather than leaving gaps. Spacing comes from the largest actor.
static func line_destinations(movers: Array, start: Vector2, end: Vector2) -> Dictionary:
	var result: Dictionary = {}
	if movers.is_empty():
		return result
	if movers.size() == 1:
		result[movers[0]] = end
		return result
	var radius: float = 0.0
	var ground: Array = []
	var air: Array = []
	for c: Commandable in movers:
		radius = maxf(radius, c.bounding_radius(CollisionLayers.Mask.MOVEMENT_OBSTRUCTION))
		(air if c.aerial != null else ground).append(c)
	var spacing: float = LineSlots.spacing_for_radius(radius)
	for group: Array in [ground, air]:
		_lay_out_on_line(group, spacing, start, end, result)
	return result


static func _lay_out_on_line(
	group: Array, spacing: float, start: Vector2, end: Vector2, into: Dictionary
) -> void:
	if group.is_empty():
		return
	var positions: Array[Vector2] = []
	var centroid: Vector2 = Vector2.ZERO
	for c: Commandable in group:
		var xz: Vector2 = VU.in_xz(c.global_position)
		positions.append(xz)
		centroid += xz
	centroid /= float(group.size())
	var slots: Array[Vector2] = LineSlots.slots(
		start, end, spacing, group.size(), LineSlots.back_toward(start, end, centroid)
	)
	var taken: Array[int] = LineSlots.assign(positions, slots, LineSlots.axis(start, end))
	for i: int in group.size():
		if taken[i] >= 0:
			into[group[i]] = slots[taken[i]]


## Each unit mapped to its own spread-out point around the order's position, so a group order
## fans the selection out instead of stacking everyone on one point. Empty when the order has a
## single destination by definition, or one actor — the caller falls back to the raw point.
## gdd/systems/ux/ui/selection-and-input.md §Group destinations fan out.
static func fanned_destinations(
	map: Map, command_type: Script, capable: Array, message: CommandMessage
) -> Dictionary:
	# Build has ONE destination: the site of the one structure being placed. FocusFire has no
	# target, so its aim point IS the position; fanning would scatter the shot, not the shooters.
	if (
		command_type == Build
		or command_type == FocusFire
		or not command_type.requires_position()
		or capable.size() <= 1
	):
		return {}
	var representative := capable[0] as Entity
	var radius: float = representative.bounding_radius(CollisionLayers.Mask.MOVEMENT_OBSTRUCTION)
	var region_radius: float = maxf(
		MIN_FAN_OUT_RADIUS, radius * FAN_OUT_RADIUS_PER_UNIT * float(capable.size())
	)
	var destination_centroid: Vector2 = message.xz_position
	var destinations: Array[Vector2] = SU.get_nonoverlapping_points(
		map,
		destination_centroid,
		radius,
		map.get_world_3d(),
		CollisionLayers.Mask.MOVEMENT_OBSTRUCTION,
		region_radius,
		capable.size()
	)
	var selection_centroid := Vector2.ZERO
	for c: Commandable in capable:
		selection_centroid += VU.in_xz((c as Entity).global_position)
	selection_centroid /= float(capable.size())
	# Destinations sorted by angle around the order's point, units by angle around their own
	# centroid, zipped: two sequences swept in the same rotational order cannot cross, so the
	# paths are non-crossing and the formation is kept by construction.
	destinations.sort_custom(
		func(a: Vector2, b: Vector2) -> bool:
			return (
				atan2(a.x - destination_centroid.x, a.y - destination_centroid.y)
				< atan2(b.x - destination_centroid.x, b.y - destination_centroid.y)
			)
	)
	var sorted_capable: Array = capable.duplicate()
	sorted_capable.sort_custom(
		func(a: Commandable, b: Commandable) -> bool:
			var a_xz: Vector2 = VU.in_xz((a as Entity).global_position)
			var b_xz: Vector2 = VU.in_xz((b as Entity).global_position)
			return (
				atan2(a_xz.x - selection_centroid.x, a_xz.y - selection_centroid.y)
				< atan2(b_xz.x - selection_centroid.x, b_xz.y - selection_centroid.y)
			)
	)
	# If scatter found fewer points than units, the rest are absent and use the raw point.
	var unit_to_destination: Dictionary = {}
	for i: int in mini(destinations.size(), sorted_capable.size()):
		unit_to_destination[sorted_capable[i]] = destinations[i]
	return unit_to_destination


## The speed a multi-unit order caps every mobile member to — the slowest mover's — or -1.0 when
## no cap applies (a single actor, or nothing in the group can move). Pure: the caller sets
## CommandMessage.match_group_speed.
static func slowest_group_speed(capable: Array) -> float:
	if capable.size() <= 1:
		return -1.0
	var movers: Array = capable.filter(func(c: Commandable) -> bool: return c.can_move())
	if movers.is_empty():
		return -1.0
	return movers.map(func(c: Commandable) -> float: return c.movement.speed).min()


static func make_defend_region_shape(
	map: Map, template: CollisionShape3D, center: Vector3
) -> CollisionShape3D:
	if template == null or template.shape == null or map == null:
		return null
	var region: CollisionShape3D = CollisionShape3D.new()
	region.shape = template.shape.duplicate()
	map.add_child(region)
	region.global_transform = Transform3D(Basis.IDENTITY, center)
	return region


static func largest_aggro_shape(units: Array) -> CollisionShape3D:
	var best: CollisionShape3D = null
	var best_radius: float = 0.0
	for c: Commandable in units:
		for shape: CollisionShape3D in c.aggro_shapes():
			var radius: float = RangeShapes.xz_radius(shape)
			if radius > best_radius:
				best_radius = radius
				best = shape
	return best


## Free `a_region` once every message in `a_messages` has been released — immediately if there
## are none.
static func lease_region_shape(region: CollisionShape3D, messages: Array[CommandMessage]) -> void:
	if messages.is_empty():
		if is_instance_valid(region):
			region.queue_free()
		return
	var remaining: Array[int] = [messages.size()]
	for m: CommandMessage in messages:
		m.unreferenced.connect(
			func() -> void:
				remaining[0] -= 1
				if remaining[0] <= 0 and is_instance_valid(region):
					region.queue_free(),
			CONNECT_ONE_SHOT
		)


## Give every actor in `a_actors` that is NOT a recipient a plain move at the same target — the
## other half of MoveCommand.bystanders_move. A plain MoveCommand deliberately: a stationary
## producer absorbs it as a rally point, as from any other right-click; and no fanning, since
## they are all heading for one place.
static func order_bystanders_to_move(
	map: Map, actors: Array, the_recipients: Array, message: CommandMessage, add_to_queue: bool
) -> void:
	for node: Variant in actors:
		var actor := node as Commandable if is_instance_valid(node) else null
		if actor == null or the_recipients.has(actor):
			continue
		var snapshot: CommandMessage = CommandMessage.deep_copy(message)
		if map != null:
			snapshot.world_position.y = map.terrain_height_at(snapshot.xz_position)
		actor.update_commands(MoveCommand.new(snapshot), add_to_queue)
#endregion
