extends GutTest

## The handshake and the ready barrier, over the loopback network: every peer learns the host's
## match, the match is ready only once every peer has loaded the same map, and a peer on another
## build or platform, a different map or a missing seat refuses it.
## gdd/systems/commands/netplay.md §What lockstep builds that rollback keeps (session setup).

const BUILD: String = "build-a"
const PLATFORM: String = "os/arch"
const MAP: String = "map-a"
const RECIPE: Dictionary = {"map_seed": 5, "rng_seed": 9}
const DELAY_SECONDS: float = 0.1


## Sessions for peers 1..`a_count` on `a_network`, peer 1 the host. `a_builds` and `a_platforms`
## override a peer's (by id).
func _sessions(
	a_network: LoopbackNetwork,
	a_count: int,
	a_builds: Dictionary = {},
	a_platforms: Dictionary = {}
) -> Array[NetSession]:
	for id: int in range(1, a_count + 1):
		a_network.endpoint(id)
	var out: Array[NetSession] = []
	for id: int in range(1, a_count + 1):
		out.append(
			NetSession.new(
				a_network.endpoint(id), 1, a_builds.get(id, BUILD), a_platforms.get(id, PLATFORM)
			)
		)
	return out


func _seats(a_count: int) -> Dictionary:
	var seats: Dictionary = {}
	for id: int in range(1, a_count + 1):
		seats[id] = id + 10
	return seats


func _exchange(
	a_network: LoopbackNetwork, a_sessions: Array[NetSession], a_rounds: int = 3
) -> void:
	for round: int in a_rounds:
		for session: NetSession in a_sessions:
			session.pump()
		a_network.step()


func test_every_peer_learns_the_hosts_match() -> void:
	var network := LoopbackNetwork.new()
	var sessions: Array[NetSession] = _sessions(network, 3)
	sessions[0].offer_match(RECIPE, _seats(3), DELAY_SECONDS)
	sessions[1].offer_match({"map_seed": 0}, {}, 9.0)
	_exchange(network, sessions)
	for session: NetSession in sessions:
		var settings: Dictionary = session.match_settings()
		assert_eq(
			settings["recipe"],
			JSON.parse_string(JSON.stringify(RECIPE)),
			"the host's, as decoded on every peer, the host's own included"
		)
		assert_eq(settings["seats"], _seats(3), "seats come back as int -> int")
		assert_almost_eq(settings["input_delay_seconds"], DELAY_SECONDS, 0.0001)


func test_ready_only_once_every_peer_has_loaded_the_same_map() -> void:
	var network := LoopbackNetwork.new()
	var sessions: Array[NetSession] = _sessions(network, 2)
	sessions[0].offer_match(RECIPE, _seats(2), DELAY_SECONDS)
	sessions[0].mark_loaded(MAP)
	_exchange(network, sessions)
	assert_false(sessions[0].is_ready(), "peer 2 has not loaded")
	assert_eq(sessions[0].waiting_on(), [2] as Array[int])
	sessions[1].mark_loaded(MAP)
	_exchange(network, sessions)
	assert_true(sessions[0].is_ready())
	assert_true(sessions[1].is_ready())


func test_not_ready_before_the_match_is_heard() -> void:
	var network := LoopbackNetwork.new()
	var sessions: Array[NetSession] = _sessions(network, 2)
	for session: NetSession in sessions:
		session.mark_loaded(MAP)
	_exchange(network, sessions)
	assert_false(sessions[1].is_ready(), "the host has offered no match")


func test_another_build_is_refused() -> void:
	var network := LoopbackNetwork.new()
	var sessions: Array[NetSession] = _sessions(network, 2, {2: "build-b"})
	_exchange(network, sessions)
	assert_string_contains(sessions[0].refusal(), "another version")
	assert_string_contains(sessions[1].refusal(), "another version")


func test_another_platform_is_refused() -> void:
	var network := LoopbackNetwork.new()
	var sessions: Array[NetSession] = _sessions(network, 2, {}, {2: "other/arch"})
	_exchange(network, sessions)
	assert_string_contains(sessions[0].refusal(), "platforms")


func test_a_different_map_is_refused() -> void:
	var network := LoopbackNetwork.new()
	var sessions: Array[NetSession] = _sessions(network, 2)
	sessions[0].offer_match(RECIPE, _seats(2), DELAY_SECONDS)
	sessions[0].mark_loaded(MAP)
	sessions[1].mark_loaded("map-b")
	_exchange(network, sessions)
	assert_string_contains(sessions[0].refusal(), "different map")
	assert_false(sessions[0].is_ready())


func test_a_peer_without_a_seat_is_refused() -> void:
	var network := LoopbackNetwork.new()
	var sessions: Array[NetSession] = _sessions(network, 2)
	sessions[0].offer_match(RECIPE, {1: 11}, DELAY_SECONDS)
	_exchange(network, sessions)
	assert_string_contains(sessions[1].refusal(), "no seat for peer 2")


func test_a_lossy_link_still_agrees() -> void:
	var network := LoopbackNetwork.new(31)
	network.loss = 0.5
	network.latency_max = 4
	var sessions: Array[NetSession] = _sessions(network, 3)
	sessions[0].offer_match(RECIPE, _seats(3), DELAY_SECONDS)
	for session: NetSession in sessions:
		session.mark_loaded(MAP)
	_exchange(network, sessions, 40)
	for session: NetSession in sessions:
		assert_true(session.is_ready(), "a lost status is replaced by the next")


func test_status_stops_once_every_peer_has_started() -> void:
	var network := LoopbackNetwork.new()
	var sessions: Array[NetSession] = _sessions(network, 2)
	sessions[0].offer_match(RECIPE, _seats(2), DELAY_SECONDS)
	for session: NetSession in sessions:
		session.mark_loaded(MAP)
		session.mark_started()
	_exchange(network, sessions)
	for session: NetSession in sessions:
		session.pump()
	assert_eq(network.in_flight(), 0, "nobody is listening any more")
