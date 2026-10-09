class_name ReplayRecorder
extends Node

## Records the match as it is played — every order the stream applies, and a state digest every
## second — and, in playback, checks the re-run against the recording's digests, reporting the
## first tick that differs. gdd/systems/commands/recording-and-replay.md §Detecting drift.
##
## Takes its digest at the start of a tick, BEFORE the stream applies that tick's orders, so a
## recording and its playback sample the same state.

## A playback's state first differed from the recording's at `tick`.
signal drift_detected(tick: int)

## How often a digest is taken. A second is coarse enough to cost nothing and fine enough to
## say where a divergence entered.
const DIGEST_PERIOD_SECONDS: float = 1.0
## The record type of a digest line, an order line, and the line that marks a recording invalid.
const DIGEST_TYPE: String = "digest"
const ORDER_TYPE: String = "order"
const INVALID_TYPE: String = "invalid"

## The recording so far. Its header is written when the match begins; its version stamp when
## it is written to disk (ReplayFile.current_version walks every piece scene once).
var replay: ReplayFile = ReplayFile.new()
## Set once debug mode changed the simulation: the recording ends there and plays back as
## refused. gdd/systems/commands/recording-and-replay.md §Debug mode.
var is_invalid: bool = false
## In playback, the first tick whose digest differed from the recording's; -1 while none has.
var first_drift_tick: int = -1

var _scenario: Scenario
## In playback: the recording's digests by tick. Empty while recording.
var _expected: Dictionary = {}
var _is_written: bool = false


func _init(a_scenario: Scenario = null) -> void:
	_scenario = a_scenario
	name = "ReplayRecorder"
	process_physics_priority = OrderStream.START_OF_TICK_PRIORITY - 1


## Start recording `a_scenario`'s match: the header now, and every order from here on.
func begin() -> void:
	replay.header = ReplayFile.header_for(_scenario, "")
	_scenario.order_stream.order_applied.connect(_on_order_applied)


## Check this run against `a_recording` instead of recording it.
func verify_against(recording: ReplayFile) -> void:
	replay = recording
	for record: Dictionary in recording.records:
		if record.get("type") == DIGEST_TYPE:
			_expected[int(record.get("tick", -1))] = str(record.get("digest", ""))


func is_verifying() -> bool:
	return not _expected.is_empty()


## The orders `a_recording` holds, in the order they were applied.
static func orders_of(recording: ReplayFile) -> Array[PlayerOrder]:
	var orders: Array[PlayerOrder] = []
	for record: Dictionary in recording.records:
		if record.get("type") == ORDER_TYPE:
			var order: PlayerOrder = PlayerOrder.from_dict(record.get("order", {}))
			if order != null:
				orders.append(order)
	return orders


## Debug mode changed the simulation: the recording ends here, marked invalid.
func invalidate(reason: String) -> void:
	if is_invalid or is_verifying():
		return
	is_invalid = true
	replay.records.append({"type": INVALID_TYPE, "tick": _scenario.tick, "reason": reason})
	if _scenario.order_stream.order_applied.is_connected(_on_order_applied):
		_scenario.order_stream.order_applied.disconnect(_on_order_applied)


## Write the recording as an autosave, deleting the oldest so AUTOSAVES_KEPT remain. Once per
## match; nothing in a headless run (the test suite, self-play), which would otherwise rotate a
## player's own autosaves out of `user://`.
func write_autosave() -> Error:
	if _is_written or is_verifying() or DisplayServer.get_name() == "headless":
		return OK
	_is_written = true
	replay.header["version"] = ReplayFile.current_version()
	DirAccess.make_dir_recursive_absolute(ReplayFile.DIRECTORY)
	for stale: String in ReplayNames.autosaves_to_delete(
		DirAccess.get_files_at(ReplayFile.DIRECTORY)
	):
		DirAccess.remove_absolute(ReplayFile.DIRECTORY + stale)
	var name_now: String = ReplayNames.autosave_name(int(Time.get_unix_time_from_system()))
	return replay.write(ReplayFile.DIRECTORY + name_now)


## Write the recording so far as a KEPT replay at `a_path` — one the rotation never deletes
## (ReplayNames). The caller has checked the name and asked before overwriting.
func write_kept(a_path: String) -> Error:
	if replay.header.get("version", "") == "":
		replay.header["version"] = ReplayFile.current_version()
	return replay.write(a_path)


func _physics_process(_a_delta: float) -> void:
	var period: int = maxi(roundi(DIGEST_PERIOD_SECONDS * TimeUtils.ticks_per_second()), 1)
	if _scenario == null or _scenario.tick % period != 0:
		return
	var digest: String = SimulationDigest.of(_scenario)
	if is_verifying():
		_check(_scenario.tick, digest)
	elif not is_invalid:
		replay.records.append({"type": DIGEST_TYPE, "tick": _scenario.tick, "digest": digest})


func _check(a_tick: int, a_digest: String) -> void:
	if first_drift_tick >= 0 or not _expected.has(a_tick):
		return
	if _expected[a_tick] != a_digest:
		first_drift_tick = a_tick
		push_error("replay drifted from its recording at tick %d" % a_tick)
		drift_detected.emit(a_tick)


func _on_order_applied(a_order: PlayerOrder, _a_indicated: Array) -> void:
	replay.records.append({"type": ORDER_TYPE, "tick": a_order.tick, "order": a_order.to_dict()})
