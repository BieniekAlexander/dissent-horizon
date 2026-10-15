extends Node

## One machine of a networked skirmish, run headless by test_TwoProcessNetplay: it hosts or joins
## a lobby on this machine, plays the match the real way — the lobby link, Play, the map generated
## off the main thread, NetMatch.build_scenario — gives one order, and once the match reaches
## `--ticks` writes what it saw to `--out` and quits. Prefixed `_`: a harness, never collected.
##
## Arguments, after `--`: --role=host|join  --port=<lobby port>  --out=<json path>  --ticks=<n>
## and optionally --address=<host's address> (a joiner dials it; a host given one listens on every
## interface, for a run across two machines) and --give-up=<seconds>.
##
## What it writes: {role, error, tick, digests: [[tick, digest]...], orders: [order...],
## desync_tick}. `error` is "" unless the run gave up.

const LOCALHOST: String = "127.0.0.1"
## Fixes the host's recipe (factions, seeds), so a failure reproduces.
const RECIPE_SEED: int = 20261014
const DELAY_TICKS: int = 3
## How long a joiner waits before dialling again when the host is not up yet.
const JOIN_RETRY_SECONDS: float = 0.5
## How long the whole run may take before it gives up and says so, unless --give-up says.
const GIVE_UP_SECONDS: float = 120.0
## What a host given an --address listens on: every interface.
const ANY_INTERFACE: String = "*"
## The tick each side gives its order on, and where the host's and joiner's armies are sent.
const ORDER_TICK: int = 150
const ORDER_TARGETS: Dictionary = {"host": Vector3(6.0, 0.0, 6.0), "join": Vector3(-6.0, 0.0, -6.0)}

var _role: String = ""
var _port: int = 0
var _out: String = ""
var _ticks: int = 0
var _address: String = LOCALHOST
var _give_up_seconds: float = GIVE_UP_SECONDS
var _link: LobbyLink = null
var _thread: Thread = null
var _launch: Dictionary = {}
var _scenario: Scenario = null
var _give_up_at: int = 0
var _join_again_at: int = 0
var _has_ordered: bool = false
var _desync_tick: int = -1
var _is_done: bool = false


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
		if pair.size() == 2:
			match pair[0]:
				"role":
					_role = pair[1]
				"port":
					_port = int(pair[1])
				"out":
					_out = pair[1]
				"ticks":
					_ticks = int(pair[1])
				"address":
					_address = pair[1]
				"give-up":
					_give_up_seconds = float(pair[1])
	_give_up_at = Time.get_ticks_msec() + int(_give_up_seconds * 1000.0)
	if _role == "host":
		_link = LobbyLink.new()
		if _link.host(_port, LOCALHOST if _address == LOCALHOST else ANY_INTERFACE) != OK:
			_finish("could not host on port %d" % _port)
			return
		_link.setup.set_player_count(2)
		_link.setup.set_team(0, 1)
		_link.setup.set_team(1, 2)
		_link.setup.set_open(1, true)
		_link.started.connect(_on_started)
	else:
		_join()


func _process(_a_delta: float) -> void:
	if _is_done:
		return
	if Time.get_ticks_msec() > _give_up_at:
		_finish("gave up at tick %d" % (_scenario.tick if _scenario != null else -1))
		return
	if _scenario == null:
		_lobby_frame()
		return
	if not _has_ordered and _scenario.tick >= ORDER_TICK:
		_has_ordered = true
		_give_order()
	if _scenario.tick >= _ticks:
		_finish("")


func _lobby_frame() -> void:
	if _link != null:
		_link.poll()
	if _role == "host" and _launch.is_empty() and _link.can_start():
		var rng := RandomNumberGenerator.new()
		rng.seed = RECIPE_SEED
		_link.start(_link.setup.recipe(rng), TimeUtils.seconds_from_ticks(DELAY_TICKS))
	if _role == "join" and _link.refusal != "" and Time.get_ticks_msec() > _join_again_at:
		_join()
	if _thread != null and not _thread.is_alive():
		var generated: Dictionary = _thread.wait_to_finish()
		_thread = null
		if generated.has("refusal"):
			_finish("map: %s" % generated["refusal"])
			return
		var built: Dictionary = NetMatch.build_scenario(_launch, generated["map"])
		if built.has("refusal"):
			_finish("build: %s" % built["refusal"])
			return
		_link.close()
		_scenario = built["scenario"]
		var match_node: NetMatch = _scenario.get_node(NodePath(NetMatch.NODE_NAME))
		match_node.desynced.connect(
			func(a_tick: int, _a_path: String) -> void: _desync_tick = a_tick
		)
		get_tree().root.add_child(_scenario)
		get_tree().current_scene = _scenario


## Dial the host — again, if it was not up yet or dropped the last attempt.
func _join() -> void:
	if _link != null:
		_link.close()
	_link = LobbyLink.new()
	_link.started.connect(_on_started)
	_link.join(_address, _port)
	_join_again_at = Time.get_ticks_msec() + int(JOIN_RETRY_SECONDS * 1000.0)


func _on_started(a_launch: Dictionary) -> void:
	_launch = a_launch
	var recipe: Dictionary = a_launch["recipe"]
	var params: MapGenerationParams = SkirmishLauncher.params_for(recipe)
	_thread = Thread.new()
	_thread.start(SkirmishLauncher.generate.bind(recipe, params))


## Send every mobile piece this machine's player owns somewhere, as its player would.
func _give_order() -> void:
	var commander: int = _scenario.local_commander_id
	var movers: Array = _scenario.commanders[commander].get_children().filter(
		func(n: Node) -> bool: return n is Actor and (n as Actor).can_move()
	)
	var message := CommandMessage.new(_scenario.map, null, null, ORDER_TARGETS[_role])
	_scenario.order_stream.submit(PlayerOrder.command(commander, MoveCommand, movers, message, {}))


func _finish(a_error: String) -> void:
	_is_done = true
	var digests: Array = []
	var orders: Array = []
	if _scenario != null and _scenario.recorder != null:
		for record: Dictionary in _scenario.recorder.replay.records:
			if record.get("type") == ReplayRecorder.DIGEST_TYPE:
				digests.append([record["tick"], record["digest"]])
			elif record.get("type") == ReplayRecorder.ORDER_TYPE:
				orders.append(record)
	var result: Dictionary = {
		"role": _role,
		"error": a_error,
		"tick": _scenario.tick if _scenario != null else -1,
		"digests": digests,
		"orders": orders,
		"desync_tick": _desync_tick,
	}
	var file: FileAccess = FileAccess.open(_out, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result))
		file.close()
	get_tree().quit()
