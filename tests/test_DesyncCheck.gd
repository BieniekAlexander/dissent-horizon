extends GutTest

## Every peer digests the start of each simulated second and sends the others its recent ones;
## the first tick whose digests differ is the desync. gdd/systems/commands/netplay.md §Decisions.

const PEER: int = 2


func _packet(a_digests: Array) -> PackedByteArray:
	return JSON.stringify({"v": DesyncCheck.WIRE_VERSION, "digests": a_digests}).to_utf8_buffer()


func test_matching_digests_are_no_desync() -> void:
	var check := DesyncCheck.new()
	check.record(30, "aaaa", "state 30")
	check.take(PEER, _packet([[30, "aaaa"]]))
	assert_false(check.has_desynced())


func test_a_differing_digest_names_its_tick_peer_and_state() -> void:
	var check := DesyncCheck.new()
	check.record(30, "aaaa", "state 30")
	check.record(60, "bbbb", "state 60")
	check.take(PEER, _packet([[30, "aaaa"], [60, "XXXX"]]))
	assert_eq(check.desync_tick, 60)
	assert_eq(check.desync_peer, PEER)
	assert_eq(check.desync_state(), "state 60", "this machine's state, to diff against theirs")


func test_a_peer_ahead_waits_for_this_machine_to_reach_the_tick() -> void:
	var check := DesyncCheck.new()
	check.take(PEER, _packet([[30, "XXXX"]]))
	assert_false(check.has_desynced(), "this machine has not digested tick 30 yet")
	check.record(30, "aaaa", "state 30")
	assert_eq(check.desync_tick, 30)


func test_every_packet_repeats_the_recent_digests() -> void:
	var check := DesyncCheck.new()
	for second: int in DesyncCheck.KEPT_DIGESTS + 2:
		check.record(second * 30, "d%d" % second, "")
	var sent: Dictionary = JSON.parse_string(check.encode().get_string_from_utf8())
	assert_eq(sent["digests"].size(), DesyncCheck.KEPT_DIGESTS, "the oldest drop off")
	var other := DesyncCheck.new()
	other.record(60, "d2", "")
	other.take(PEER, check.encode())
	assert_false(other.has_desynced(), "a lost packet costs nothing: the next one carries it")


func test_a_packet_of_another_version_is_ignored() -> void:
	var check := DesyncCheck.new()
	check.record(30, "aaaa", "")
	check.take(PEER, JSON.stringify({"v": -1, "digests": [[30, "XXXX"]]}).to_utf8_buffer())
	assert_false(check.has_desynced())


func test_a_declared_desync_stands() -> void:
	var check := DesyncCheck.new()
	check.declare(12, PEER)
	assert_eq(check.desync_tick, 12)
	check.declare(40, 3)
	assert_eq(check.desync_tick, 12, "the first one found stands")
