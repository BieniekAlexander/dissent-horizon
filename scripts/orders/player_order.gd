class_name PlayerOrder
extends RefCounted

## One thing a player told the simulation: the unit of the order stream that replay records and
## plays back, and the shape a networked input would take. Plain data — every piece named by
## its spawn serial (Entity.spawn_serial), every resource by its id — so it serializes as one
## JSON line and means the same thing on every run of the seed.
## gdd/systems/commands/recording-and-replay.md §The order stream.
##
## Built by the controller from the selection and the modifiers held, applied by
## OrderDispatcher at the start of a tick (OrderStream).

## What kind of order this is; `data` holds that kind's fields.
##   COMMAND   — a command at a selection: {command, actors, queue, narrow, broaden, standing,
##               line, message} (see command()).
##   HOLD_FIRE — the hold-fire toggle over a set of actors: {actors, queue} (queue: the additive
##               modifier was held, so it waits its turn in each actor's queue).
##   AUTOCAST  — a commander-wide autocast toggle: {ability}.
##   CANCEL_PURCHASE — cancel queued purchases: {owner, purchases} (PurchaseTransaction ids).
##   CANCEL_JOB — cancel a producer's job: {producer, job} (the job's index in its queue).
##   RELEASE_OCCUPANT — let one of the host's own side out of a garrison: {host, occupant}.
##   UNLOCK_SANCTION — buy a sanction-grid cell: {tier, column}.
##   DROP — land a start-of-round drop: {drop, aim} (Deployment.Drop, a world XZ).
##   PENDING_COMMAND — store a command on purchases whose unit does not exist yet:
##               {owner, purchases, command, queue, message}.
##   DIALOG    — resolve a scenario dialog: {dialog, secondary} (ScenarioDialog.serial, and
##               whether its second option was taken). The one kind applied while the world is
##               paused, since a dialog is what pauses it.
enum Kind {
	COMMAND,
	HOLD_FIRE,
	AUTOCAST,
	CANCEL_PURCHASE,
	CANCEL_JOB,
	RELEASE_OCCUPANT,
	UNLOCK_SANCTION,
	DROP,
	PENDING_COMMAND,
	DIALOG,
}

var kind: Kind
## The commander whose player gave it.
var commander_id: int
## The tick it was applied on; -1 until then.
var tick: int = -1
var data: Dictionary = {}


func _init(a_kind: Kind = Kind.COMMAND, a_commander_id: int = 0, a_data: Dictionary = {}) -> void:
	kind = a_kind
	commander_id = a_commander_id
	data = a_data


## The order as one JSON-able dictionary.
func to_dict() -> Dictionary:
	return {"kind": Kind.keys()[kind], "commander": commander_id, "tick": tick, "data": data}


## The order a dictionary from to_dict describes, or null when it names no kind. JSON brings
## numbers back as floats; the readers below take that into account.
static func from_dict(d: Dictionary) -> PlayerOrder:
	var kind_name: String = str(d.get("kind", ""))
	if not Kind.has(kind_name):
		return null
	var order := PlayerOrder.new(Kind[kind_name], int(d.get("commander", 0)), d.get("data", {}))
	order.tick = int(d.get("tick", -1))
	return order


#region COMMAND
## A command at a selection. `a_actors` is the WHOLE selection: which of them take it is decided
## when it is applied (OrderDispatcher.recipients), the same rule the controller previews with.
static func command(
	commander_id: int,
	command_type: Script,
	actors: Array,
	message: CommandMessage,
	modifiers: Dictionary
) -> PlayerOrder:
	return (
		PlayerOrder
		. new(
			Kind.COMMAND,
			commander_id,
			{
				"command": command_type.resource_path,
				"actors": serials_of(actors),
				"queue": bool(modifiers.get("queue", false)),
				"narrow": bool(modifiers.get("narrow", false)),
				"broaden": bool(modifiers.get("broaden", false)),
				"standing": bool(modifiers.get("standing", false)),
				"line": modifiers.get("line", []),
				"message": message_to_dict(message),
			}
		)
	)


func command_type() -> Script:
	var path: String = str(data.get("command", ""))
	return load(path) as Script if ResourceLoader.exists(path) else null


## The fields of a message a player order can set. Everything else on a CommandMessage is
## derived when the order is applied (the purchase, the blueprint, a Defend region, the
## sibling token).
static func message_to_dict(message: CommandMessage) -> Dictionary:
	var target: Entity = message.target if is_instance_valid(message.target) else null
	var tool: Tool = message.tool
	var at: Vector3 = message.world_position
	return {
		"target": target.spawn_serial if target != null else 0,
		"tool": tool.command_name if tool != null else "",
		"variant": tool.variant_index() if tool != null else -1,
		"position": [at.x, at.y, at.z],
		"ability": String(message.ability_type) if message.ability_type != null else "",
		"sanction": message.sanction.sanction_name if message.sanction != null else "",
		"quarter_turns": message.quarter_turns,
		"defer_if_unaffordable": message.defer_if_unaffordable,
	}


## The message `d` describes, its pieces looked up in `a_scenario` and its sanction in
## `a_commander`'s grid. A piece that has since been freed reads as no target.
static func message_from_dict(
	d: Dictionary, map: Map, scenario: Scenario, commander: Commander
) -> CommandMessage:
	var message := CommandMessage.new(map)
	var serial: int = int(d.get("target", 0))
	if serial != 0 and scenario != null:
		message.target = scenario.piece_by_serial(serial)
	var tool_name: String = str(d.get("tool", ""))
	if not tool_name.is_empty():
		var tool: Tool = Tool.for_name(tool_name)
		var variant: int = int(d.get("variant", -1))
		message.tool = tool.with_variant(variant) if tool != null and variant >= 0 else tool
	var at: Array = d.get("position", [0.0, 0.0, 0.0])
	message.world_position = Vector3(float(at[0]), float(at[1]), float(at[2]))
	var ability: String = str(d.get("ability", ""))
	message.ability_type = StringName(ability) if not ability.is_empty() else null
	var sanction: String = str(d.get("sanction", ""))
	if not sanction.is_empty() and commander != null:
		message.sanction = commander.sanction_named(sanction)
	message.quarter_turns = int(d.get("quarter_turns", 0))
	message.defer_if_unaffordable = bool(d.get("defer_if_unaffordable", true))
	return message


#endregion


## The spawn serials of the pieces among `a_nodes` that have one.
static func serials_of(nodes: Array) -> Array:
	var out: Array = []
	for node: Variant in nodes:
		if is_instance_valid(node) and node is Entity and (node as Entity).spawn_serial != 0:
			out.append((node as Entity).spawn_serial)
	return out


## The live pieces `a_serials` name in `a_scenario`, in order; freed ones are dropped.
static func pieces_of(serials: Array, scenario: Scenario) -> Array:
	var out: Array = []
	if scenario == null:
		return out
	for serial: Variant in serials:
		var piece: Entity = scenario.piece_by_serial(int(serial))
		if piece != null:
			out.append(piece)
	return out
