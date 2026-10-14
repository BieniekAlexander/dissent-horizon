extends GutTest

## One connection, several conversations: a message reaches only the channel it was sent on.
## gdd/systems/commands/netplay.md §What lockstep builds that rollback keeps.


func test_a_message_reaches_only_its_own_channel() -> void:
	var network := LoopbackNetwork.new()
	var a := TransportMux.new(network.endpoint(1))
	var b := TransportMux.new(network.endpoint(2))
	var b_turns: NetTransport = b.channel(TransportMux.TURNS)
	var b_session: NetTransport = b.channel(TransportMux.SESSION)
	a.channel(TransportMux.TURNS).send(2, "turn".to_utf8_buffer())
	a.channel(TransportMux.SESSION).send(2, "hello".to_utf8_buffer())
	network.step()
	var turns: Array = b_turns.receive()
	var session: Array = b_session.receive()
	assert_eq(turns.size(), 1)
	assert_eq((turns[0][1] as PackedByteArray).get_string_from_utf8(), "turn")
	assert_eq(int(turns[0][0]), 1, "named by the sender")
	assert_eq(session.size(), 1)
	assert_eq((session[0][1] as PackedByteArray).get_string_from_utf8(), "hello")


func test_a_message_for_a_channel_nobody_holds_is_dropped() -> void:
	var network := LoopbackNetwork.new()
	var a := TransportMux.new(network.endpoint(1))
	var b := TransportMux.new(network.endpoint(2))
	var b_turns: NetTransport = b.channel(TransportMux.TURNS)
	a.channel(TransportMux.SESSION).send(2, "hello".to_utf8_buffer())
	network.endpoint(1).send(2, PackedByteArray())
	network.step()
	assert_eq(b_turns.receive(), [])


func test_a_channel_answers_for_the_connection() -> void:
	var network := LoopbackNetwork.new()
	network.endpoint(2)
	var channel: NetTransport = TransportMux.new(network.endpoint(1)).channel(TransportMux.TURNS)
	assert_eq(channel.local_id(), 1)
	assert_eq(channel.remote_ids(), [2] as Array[int])
