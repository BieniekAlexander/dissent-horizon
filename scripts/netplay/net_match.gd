class_name NetMatch
extends Node

## A networked match inside its scenario: holds the world from the scenario's first frame until
## every peer has loaded the same map (NetSession), then plays it in lockstep — a Lockstep over
## the turn channel, joined to the scenario's OrderStream. gdd/systems/commands/netplay.md §Rules
## (tick 0 runs only once every peer reports its map and scenario loaded).
##
## Added to the scenario BEFORE it enters the tree, so its first physics frame holds the world
## before anything simulates. Loaded means in the tree with its map built; what boots after that
## (the opening force, on NavManager.navmesh_ready) waits on the physics frames the hold stops,
## so it lands on the same tick after the release on every machine.
##
## PLANNED: built by the Multiplayer lobby, which hands it the session the lobby agreed the match
## in; until then, tests build it.

## The match has started: every peer loaded the same map and the world was released.
signal started
## The match will not start, and why. The world stays held.
signal refused(reason: String)
## A peer's simulation differs from this one's at `a_tick`: the match is over, the world held for
## good, and this machine's state for that tick written to `a_path` for diffing.
signal desynced(a_tick: int, a_path: String)

## The node's name in its scenario, which is how Scenario.is_networked() finds it.
const NODE_NAME: StringName = &"NetMatch"
## How long a peer may be waited on before this machine votes it out (Lockstep.vote_out): it
## then forfeits, once every peer still playing has voted the same (netplay.md §Decisions, a
## silent peer).
const FORFEIT_SECONDS: float = 30.0
## How long a wait lasts before the readout names who it is on: long enough that a turn merely a
## frame late does not flash it, and the first second as the decision asks.
const READOUT_AFTER_SECONDS: float = 1.0
## The readout's place and size: below the top HUD bar, readable at a glance.
const READOUT_TOP_MARGIN: float = 64.0
const READOUT_FONT_SIZE: int = 22
## Where a desync's state is written, one file per machine.
const DESYNC_DIRECTORY: String = "user://desync"
## Ahead of the order stream, so the hold is taken before anything in the frame simulates.
const START_OF_FRAME_PRIORITY: int = OrderStream.START_OF_TICK_PRIORITY - 100

var session: NetSession
## Null until the match starts.
var lockstep: Lockstep = null

var _turns: NetTransport
## The channel digests are exchanged on, or null in a test that checks nothing.
var _digests: NetTransport = null
var _desync_check: DesyncCheck = DesyncCheck.new()
## The last tick digested, so a held tick is digested once.
var _last_digest_tick: int = -1
var _has_reported_desync: bool = false
## FORFEIT_SECONDS, per match: a test waits less.
var forfeit_after_seconds: float = FORFEIT_SECONDS
## Commander -> when (real time, msec) this machine began waiting on it. Real time, because a
## wait is real time; what it leads to, a forfeit, is agreed by vote and applied on an agreed tick.
var _waiting_since: Dictionary = {}
var _readout: Label = null
## The connection under every channel, closed when the match leaves the tree. Null in a test
## that owns its own.
var _connection: NetTransport = null
var _scenario: Scenario
var _is_holding: bool = false
var _has_reported_refusal: bool = false


## A match agreed through `a_session`, its turns sent over `a_turns` (the turn channel of the same
## connection: TransportMux).
func _init(
	a_session: NetSession = null,
	a_turns: NetTransport = null,
	a_connection: NetTransport = null,
	a_digests: NetTransport = null
) -> void:
	session = a_session
	_turns = a_turns
	_connection = a_connection
	_digests = a_digests
	name = NODE_NAME
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = START_OF_FRAME_PRIORITY


func _ready() -> void:
	_scenario = get_parent() as Scenario


func _exit_tree() -> void:
	if _connection != null:
		_connection.close()
		_connection = null


## The networked match `a_launch` describes (LobbyLink.started), on the generated map `a_map`:
## the skirmish SkirmishLauncher builds, played from this machine's seat, with a NetMatch over
## the launch's transport. {scenario} not yet in the tree, or {refusal}. Main thread.
static func build_scenario(a_launch: Dictionary, a_map: GeneratedMap) -> Dictionary:
	var built: Dictionary = SkirmishLauncher.build(a_launch["recipe"], a_map)
	if built.has("refusal"):
		return built
	var scenario: Scenario = built["scenario"]
	var local_id: int = int(a_launch["local_id"])
	var seats: Dictionary = a_launch["seats"]
	scenario.local_commander_id = int(seats.get(local_id, -1))
	var connection: NetTransport = a_launch["transport"]
	var mux := TransportMux.new(connection)
	var session := NetSession.new(mux.channel(TransportMux.SESSION), SkirmishSetup.HOST_PEER)
	session.offer_match(a_launch["recipe"], seats, float(a_launch["input_delay_seconds"]))
	var turns: NetTransport = mux.channel(TransportMux.TURNS)
	var digests: NetTransport = mux.channel(TransportMux.DIGESTS)
	scenario.add_child(NetMatch.new(session, turns, connection, digests))
	return {"scenario": scenario}


func has_started() -> bool:
	return lockstep != null


func _physics_process(_a_delta: float) -> void:
	if _scenario == null or session == null:
		return
	if not session.is_loaded():
		session.mark_loaded(MapDigest.of(_scenario))
	session.pump()
	if has_started():
		_watch_for_silence()
		_check_for_desync()
		return
	if session.refusal() != "":
		_hold()
		if not _has_reported_refusal:
			_has_reported_refusal = true
			refused.emit(session.refusal())
		return
	if not session.is_ready():
		_hold()
		return
	_start()


func _start() -> void:
	var settings: Dictionary = session.match_settings()
	var seats: Dictionary = settings["seats"]
	assert(
		(
			_scenario.local_commander_id < 1
			or _scenario.local_commander_id == int(seats[_turns.local_id()])
		),
		"NetMatch: the scenario was built for another seat than this machine's"
	)
	var others: Dictionary = {}
	for peer: int in seats:
		if peer != _turns.local_id():
			others[peer] = seats[peer]
	lockstep = Lockstep.new(
		_turns,
		int(seats[_turns.local_id()]),
		others,
		float(settings["input_delay_seconds"]),
		_scenario.tick
	)
	_scenario.order_stream.join_lockstep(lockstep)
	session.mark_started()
	_release()
	started.emit()


## Time how long each commander has held the match up; vote it out at forfeit_after_seconds, and
## name who the match is waiting on, and how long until they forfeit.
func _watch_for_silence() -> void:
	var now: int = Time.get_ticks_msec()
	var waiting: Array[int] = []
	if not lockstep.can_run(_scenario.tick):
		for commander: int in lockstep.waiting_on(_scenario.tick):
			if not lockstep.has_voted_out(commander):
				waiting.append(commander)
	for commander: int in _waiting_since.keys():
		if not waiting.has(commander):
			_waiting_since.erase(commander)
	var lines: PackedStringArray = []
	for commander: int in waiting:
		if not _waiting_since.has(commander):
			_waiting_since[commander] = now
		var waited: float = float(now - int(_waiting_since[commander])) / 1000.0
		if waited >= forfeit_after_seconds:
			lockstep.vote_out(commander)
		elif waited >= READOUT_AFTER_SECONDS:
			lines.append(
				(
					"Waiting for Player %d… forfeits in %d s"
					% [commander, ceili(forfeit_after_seconds - waited)]
				)
			)
	_show_readout("\n".join(lines))


## The waiting readout: shown while it has something to say.
func _show_readout(a_text: String) -> void:
	if _readout == null:
		if a_text == "":
			return
		var layer := CanvasLayer.new()
		layer.name = "WaitingReadout"
		_readout = Label.new()
		_readout.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_readout.position.y = READOUT_TOP_MARGIN
		_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_readout.add_theme_font_size_override("font_size", READOUT_FONT_SIZE)
		layer.add_child(_readout)
		add_child(layer)
	_readout.text = a_text
	_readout.visible = a_text != ""


func waiting_readout() -> String:
	return _readout.text if _readout != null and _readout.visible else ""


## Digest the start of every simulated second, exchange digests with every peer, and end the
## match the first time any differs — or a peer has sent two different turns for one tick.
func _check_for_desync() -> void:
	if _has_reported_desync or _digests == null:
		return
	for message: Array in _digests.receive():
		_desync_check.take(int(message[0]), message[1])
	var period: int = maxi(
		roundi(ReplayRecorder.DIGEST_PERIOD_SECONDS * TimeUtils.ticks_per_second()), 1
	)
	var tick: int = _scenario.tick
	if tick % period == 0 and tick != _last_digest_tick:
		_last_digest_tick = tick
		var state: String = SimulationDigest.state_string(_scenario)
		var digest: String = state.sha256_text().substr(0, SimulationDigest.DIGEST_LENGTH)
		_desync_check.record(tick, digest, state)
		var bytes: PackedByteArray = _desync_check.encode()
		for peer: int in _digests.remote_ids():
			_digests.send(peer, bytes)
	if lockstep.contradiction_tick >= 0:
		_desync_check.declare(lockstep.contradiction_tick, lockstep.contradiction_commander)
	if _desync_check.has_desynced():
		_end_by_desync()


## Hold the world for good, write this machine's state for the tick that differed, and end the
## match with a desync notice. Every peer finds the same mismatch and does the same.
func _end_by_desync() -> void:
	_has_reported_desync = true
	_hold()
	var tick: int = _desync_check.desync_tick
	DirAccess.make_dir_recursive_absolute(DESYNC_DIRECTORY)
	var path: String = (
		"%s/desync_seed%d_tick%d_peer%d.txt"
		% [DESYNC_DIRECTORY, _scenario.rng_seed, tick, _turns.local_id()]
	)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(_desync_check.desync_state())
		file.close()
	_scenario.end_match(-1, "Desync — the match cannot go on (tick %d)" % tick)
	desynced.emit(tick, path)


func _hold() -> void:
	var clock: SimulationClock = _clock()
	if clock != null and not _is_holding:
		clock.hold(SimulationClock.REASON_NETWORK_WAIT)
		_is_holding = true


func _release() -> void:
	var clock: SimulationClock = _clock()
	if clock != null and _is_holding:
		clock.release(SimulationClock.REASON_NETWORK_WAIT)
		_is_holding = false


func _clock() -> SimulationClock:
	var manager: ScenarioTriggerManager = _scenario.trigger_manager()
	return manager.simulation_clock if manager != null else null
