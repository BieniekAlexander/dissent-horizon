class_name MatchLog
extends Node

## THE MATCH'S EVENT LOG: what happened, in order, as plain JSON-ready dictionaries. Every
## after-the-fact view of a match — the summary screen, a statistic, an analysis of a self-play
## run — reads this and never the game, so the same numbers come out live and from a file.
## Schema and what each event lets you derive: gdd/systems/scenario-scripting/match-log.md.
##
## Append-only, which is the point of a log and the one place the project keeps a history: the
## bot's world model deliberately keeps none (gdd/systems/ai/world-model.md §The model).
##
## Owned by Scenario, which records the match's start and end; purchases and constructions
## arrive by commander signal, and resources are SAMPLED on a period, because energy changes
## every tick and an event per change would be most of the file.

## Seconds of simulation between resource samples.
const STATS_PERIOD_SECONDS: float = 5.0
## Decimal places a time in seconds is written with: a tick is a thirtieth of a second.
const TIME_STEP_SECONDS: float = 0.01

const MATCH_STARTED: String = "match_started"
const PURCHASE_FUNDED: String = "purchase_funded"
const PURCHASE_REFUNDED: String = "purchase_refunded"
const PURCHASE_COMPLETED: String = "purchase_completed"
const CONSTRUCTION_FINISHED: String = "construction_finished"
const STATS: String = "stats"
const COMMANDER_ELIMINATED: String = "commander_eliminated"
const MATCH_ENDED: String = "match_ended"

## What a purchase was for, as written in its events.
const KIND_UNIT: String = "unit"
const KIND_STRUCTURE: String = "structure"
const KIND_UPGRADE: String = "upgrade"

## Every event recorded, oldest first. Each carries `tick`, `t` (seconds) and `type`.
var events: Array[Dictionary] = []

## Supplies the clock and the commanders; null for a log built outside a scenario (a test),
## whose events are stamped at tick 0.
var _scenario: Scenario = null
var _next_stats_tick: int = 0
var _is_ended: bool = false


## Start recording `a_scenario`'s match: write its header and listen to every commander.
func begin(a_scenario: Scenario) -> void:
	_scenario = a_scenario
	var commanders: Array = []
	for slot: PlayerSlot in a_scenario.player_slots:
		if slot == null or slot.commander == null:
			continue
		listen_to(slot.commander)
		(
			commanders
			. append(
				{
					"id": slot.commander.id,
					"faction":
					slot.faction.resource_path.get_file().get_basename() if slot.faction else "",
					"is_bot": slot.is_bot,
				}
			)
		)
	a_scenario.commander_eliminated.connect(
		func(a_id: int) -> void: record(COMMANDER_ELIMINATED, {"commander": a_id})
	)
	record(
		MATCH_STARTED,
		{
			"scenario": a_scenario.scene_file_path,
			"seed": a_scenario.rng_seed,
			"win_condition": Scenario.WinCondition.keys()[a_scenario.win_condition],
			"commanders": commanders,
		}
	)


## Record `a_commander`'s purchases and finished constructions.
func listen_to(a_commander: Commander) -> void:
	a_commander.purchase_progressed.connect(_on_purchase_progressed.bind(a_commander))
	a_commander.construction_finished.connect(_on_construction_finished.bind(a_commander))


## Record the match's end, with a final resource sample so every series reaches it. `a_winner`
## is a commander id, or -1 for none. Recorded once; a second end is ignored.
func end(a_winner: int) -> void:
	if _is_ended:
		return
	_is_ended = true
	_sample_stats()
	record(MATCH_ENDED, {"winner": a_winner})


func is_ended() -> bool:
	return _is_ended


## Append one event of `a_type` carrying `a_fields`, stamped with the current time.
func record(a_type: String, a_fields: Dictionary = {}) -> void:
	var tick: int = _scenario.tick if _scenario != null else 0
	var event: Dictionary = {
		"tick": tick,
		"t": snappedf(TimeUtils.seconds_from_ticks(tick), TIME_STEP_SECONDS),
		"type": a_type,
	}
	event.merge(a_fields)
	events.append(event)


## The log as JSON lines: one event per line, oldest first.
func to_jsonl() -> String:
	return "".join(events.map(func(e: Dictionary) -> String: return JSON.stringify(e) + "\n"))


## Write the log to `a_path` as gzipped JSON lines, which plain `gunzip` reads.
func write_gzip(a_path: String) -> Error:
	var file: FileAccess = FileAccess.open(a_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(to_jsonl().to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP))
	file.close()
	return OK


## The events in JSON-lines `text`, oldest first. Numbers come back as floats, as JSON has them.
static func parse_jsonl(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for line: String in text.split("\n", false):
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary:
			out.append(parsed)
	return out


func _physics_process(_a_delta: float) -> void:
	if _scenario == null or _is_ended or _scenario.tick < _next_stats_tick:
		return
	_sample_stats()
	_next_stats_tick = _scenario.tick + TimeUtils.ticks_from_seconds(STATS_PERIOD_SECONDS)


## One STATS event per standing commander: its resources and what its units are worth.
func _sample_stats() -> void:
	if _scenario == null:
		return
	for slot: PlayerSlot in _scenario.player_slots:
		var c: Commander = slot.commander if slot != null else null
		if c == null or c.is_eliminated:
			continue
		record(
			STATS,
			{
				"commander": c.id,
				"energy": c.energy,
				"dominion": c.dominion,
				"infrastructure_provided": c.infrastructure_provided,
				"infrastructure_required": c.infrastructure_required,
				"army_value": (c as Bot).army_resource_value() if c is Bot else 0.0,
			}
		)


func _on_purchase_progressed(
	a_transaction: PurchaseTransaction, a_stage: StringName, a_commander: Commander
) -> void:
	var type: String = (
		{
			&"funded": PURCHASE_FUNDED,
			&"refunded": PURCHASE_REFUNDED,
			&"completed": PURCHASE_COMPLETED,
		}
		. get(a_stage, "")
	)
	if type == "":
		return
	record(
		type,
		{
			"commander": a_commander.id,
			"purchase": a_transaction.id,
			"piece": String(a_transaction.type),
			"kind": kind_of(a_transaction),
			"energy": a_transaction.energy_cost,
			"dominion": a_transaction.dominion_cost,
		}
	)


func _on_construction_finished(a_structure: Actor, a_commander: Commander) -> void:
	record(CONSTRUCTION_FINISHED, {"commander": a_commander.id, "piece": String(a_structure.id)})


## What `transaction` buys: a structure for a build, otherwise an upgrade or a unit.
static func kind_of(transaction: PurchaseTransaction) -> String:
	if transaction.kind == PurchaseTransaction.Kind.BUILD:
		return KIND_STRUCTURE
	return KIND_UPGRADE if UpgradeCatalog.is_upgrade(transaction.type) else KIND_UNIT
