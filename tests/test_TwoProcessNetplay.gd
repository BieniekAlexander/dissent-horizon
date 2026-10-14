extends GutTest

## Two machines play one networked skirmish: two headless Godot processes on this machine, each
## a real peer (tests/_netplay_peer.tscn) — lobby, Play, map generation, NetMatch, lockstep over
## ENet — each giving an order. They must reach the same tick having applied the same orders and
## digested the same simulation every second, with no desync. The end-to-end check that the
## netplay stack keeps two machines in step. gdd/systems/commands/netplay.md §Decisions (testing).

const PEER_SCENE: String = "res://tests/_netplay_peer.tscn"
## Ticks the match is played for: past both orders (at tick 150) and well into the opening.
const MATCH_TICKS: int = 600
## How long the test waits for both peers: real time — two map generations and a match.
const WAIT_SECONDS: float = 150.0
const OUT_DIRECTORY: String = "user://netplay_test"

var _pids: Array[int] = []


func after_each() -> void:
	for pid: int in _pids:
		if OS.is_process_running(pid):
			OS.kill(pid)
	_pids.clear()


func test_two_machines_play_the_same_match() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIRECTORY)
	var port: int = _free_port()
	var outs: Dictionary = {}
	for role: String in ["host", "join"]:
		var out: String = ProjectSettings.globalize_path("%s/%s.json" % [OUT_DIRECTORY, role])
		DirAccess.remove_absolute(out)
		outs[role] = out
		_pids.append(OS.create_process(OS.get_executable_path(), _arguments(role, port, out)))
	var deadline: int = Time.get_ticks_msec() + int(WAIT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if outs.values().all(FileAccess.file_exists):
			break
		await get_tree().process_frame
	var results: Dictionary = {}
	for role: String in outs:
		assert_true(FileAccess.file_exists(outs[role]), "%s finished within the wait" % role)
		if FileAccess.file_exists(outs[role]):
			results[role] = JSON.parse_string(FileAccess.get_file_as_string(outs[role]))
	if results.size() < 2:
		return
	var host: Dictionary = results["host"]
	var join: Dictionary = results["join"]
	for result: Dictionary in [host, join]:
		assert_eq(result["error"], "", "%s ran to the end" % result["role"])
		assert_gte(int(result["tick"]), MATCH_TICKS)
		assert_eq(int(result["desync_tick"]), -1, "%s found no desync" % result["role"])
	assert_eq(host["orders"].size(), 2, "both players' orders were applied")
	assert_eq(join["orders"], host["orders"], "the same orders on the same ticks")
	var compared: int = mini(host["digests"].size(), join["digests"].size())
	assert_gt(compared, MATCH_TICKS / 60, "a digest every second, on both")
	assert_eq(join["digests"].slice(0, compared), host["digests"].slice(0, compared))


func _arguments(a_role: String, a_port: int, a_out: String) -> PackedStringArray:
	return PackedStringArray(
		[
			"--headless",
			"--path",
			ProjectSettings.globalize_path("res://"),
			"--fixed-fps",
			"30",
			PEER_SCENE,
			"--",
			"--role=%s" % a_role,
			"--port=%d" % a_port,
			"--out=%s" % a_out,
			"--ticks=%d" % MATCH_TICKS,
		]
	)


## A port nothing on this machine is listening on right now.
func _free_port() -> int:
	var probe := ENetConnection.new()
	probe.create_host_bound("127.0.0.1", 0, 1, 1)
	var port: int = probe.get_local_port()
	probe.destroy()
	return port
