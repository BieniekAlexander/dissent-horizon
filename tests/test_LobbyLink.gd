extends GutTest

## The networked lobby over real sockets on this machine: a joiner is seated in the first free
## open slot and may move, one on another build or with no slot free is refused, a joiner who
## leaves frees their slot, and Play hands every peer the same match and forms the match's mesh.
## gdd/systems/commands/netplay.md §Decisions (entry).

const LOCALHOST: String = "127.0.0.1"
const BUILD: String = "build"
const PLATFORM: String = "os/arch"
## How long a test waits on sockets: real time, so bounded by the wall clock, never by frames.
const WAIT_SECONDS: float = 5.0
const RECIPE: Dictionary = {"map_seed": 3, "rng_seed": 4}
const DELAY_SECONDS: float = 0.1

var _links: Array[LobbyLink] = []


func after_each() -> void:
	for link: LobbyLink in _links:
		link.close()
		link.close_transport()
	_links.clear()


## A hosted lobby of `a_players`, with slots `a_open` marked open.
func _host(a_players: int = 3, a_open: Array = [1, 2]) -> LobbyLink:
	var link := LobbyLink.new(BUILD, PLATFORM)
	assert_eq(link.host(0, LOCALHOST), OK)
	link.setup.set_player_count(a_players)
	for slot: int in a_open:
		link.setup.set_open(slot, true)
	link.setup.set_team(0, 1)
	link.setup.set_team(1, 2)
	_links.append(link)
	return link


func _join(a_host: LobbyLink, a_build: String = BUILD) -> LobbyLink:
	var link := LobbyLink.new(a_build, PLATFORM)
	assert_eq(link.join(LOCALHOST, a_host.lobby_port()), OK)
	_links.append(link)
	return link


## Poll every link (and, after Play, every match transport) until `a_done` holds or time runs out.
func _until(a_done: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(WAIT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		for link: LobbyLink in _links:
			link.poll()
			if link.transport != null:
				link.transport.receive()
		if a_done.call():
			return true
		await get_tree().process_frame
	return false


func _seated(a_link: LobbyLink) -> bool:
	return a_link.setup != null and a_link.setup.slot_of(a_link.local_id) > 0


func test_a_joiner_is_seated_in_the_first_free_open_slot() -> void:
	var host: LobbyLink = _host()
	var joiner: LobbyLink = _join(host)
	assert_true(await _until(_seated.bind(joiner)))
	assert_eq(joiner.local_id, SkirmishSetup.HOST_PEER + 1)
	assert_eq(host.setup.slot_of(joiner.local_id), 1)
	assert_eq(joiner.setup.slot_of(joiner.local_id), 1, "the joiner sees the host's setup")
	assert_eq(host.members(), [1, 2] as Array[int])


func test_a_joiner_may_move_to_another_open_slot() -> void:
	var host: LobbyLink = _host()
	var joiner: LobbyLink = _join(host)
	assert_true(await _until(_seated.bind(joiner)))
	joiner.claim(2)
	assert_true(await _until(func() -> bool: return joiner.setup.slot_of(joiner.local_id) == 2))
	assert_eq(host.setup.peer_in(1), 0, "the slot it left is free")


func test_a_joiner_with_no_open_slot_free_is_refused() -> void:
	var host: LobbyLink = _host(3, [])
	var joiner: LobbyLink = _join(host)
	assert_true(await _until(func() -> bool: return joiner.refusal != ""))
	assert_string_contains(joiner.refusal, "No open slot")
	assert_eq(host.members(), [1] as Array[int])


func test_a_joiner_on_another_build_is_refused() -> void:
	var host: LobbyLink = _host()
	var joiner: LobbyLink = _join(host, "another-build")
	assert_true(await _until(func() -> bool: return joiner.refusal != ""))
	assert_string_contains(joiner.refusal, "another version")


func test_a_joiner_who_leaves_frees_their_slot() -> void:
	var host: LobbyLink = _host()
	var joiner: LobbyLink = _join(host)
	assert_true(await _until(_seated.bind(joiner)))
	joiner.close()
	assert_true(await _until(func() -> bool: return host.setup.peer_in(1) == 0))
	assert_eq(host.members(), [1] as Array[int])


func test_play_hands_every_peer_the_same_match_and_forms_the_mesh() -> void:
	var host: LobbyLink = _host()
	var a: LobbyLink = _join(host)
	var b: LobbyLink = _join(host)
	assert_true(await _until(func() -> bool: return _seated(a) and _seated(b) and host.can_start()))
	var launches: Dictionary = {}
	for link: LobbyLink in [host, a, b]:
		link.started.connect(func(l: Dictionary) -> void: launches[link.local_id] = l)
	host.start(RECIPE, DELAY_SECONDS)
	assert_true(await _until(func() -> bool: return launches.size() == 3))
	for id: int in launches:
		var launch: Dictionary = launches[id]
		assert_eq(
			JSON.stringify(launch["recipe"]),
			JSON.stringify(JSON.parse_string(JSON.stringify(RECIPE))),
			"the host's recipe, as every peer decodes it"
		)
		assert_eq(launch["seats"], host.setup.match_seats())
		assert_almost_eq(float(launch["input_delay_seconds"]), DELAY_SECONDS, 0.0001)
		assert_eq(launch["local_id"], id)
	assert_true(
		await _until(_all_meshed.bind([host, a, b])),
		"every peer reaches every other, joiners included"
	)


func _all_meshed(a_links: Array) -> bool:
	return a_links.all(func(l: LobbyLink) -> bool: return l.transport.is_connected_to_all())


## At Play the host closes its lobby first, so the joiner's own close meets a server peer that
## is already gone — which must not try to disconnect it again.
func test_a_joiner_closes_cleanly_after_the_host_has_gone() -> void:
	var host: LobbyLink = _host()
	var joiner: LobbyLink = _join(host)
	assert_true(await _until(_seated.bind(joiner)))
	host.close()
	assert_true(await _until(func() -> bool: return joiner.refusal != ""))
	joiner.close()
	assert_engine_error_count(0)
