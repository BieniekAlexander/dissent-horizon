extends GutTest

## The skirmish lobby, networked: the host opens a slot and a joiner is seated in it; the
## joiner sees the setup but edits nothing, and may take another open slot; Play is the host's,
## and waits until every open slot is taken. Two lobbies in one process, over real sockets on
## this machine; Play itself is not pressed, since it generates a real map.
## gdd/systems/ux/ui/menus.md §Multiplayer.

const LOCALHOST: String = "127.0.0.1"
## How long a test waits on sockets: real time, so bounded by the wall clock.
const WAIT_SECONDS: float = 5.0

var _host_lobby: SkirmishLobby
var _join_lobby: SkirmishLobby


func before_each() -> void:
	var host_link := LobbyLink.new("build")
	assert_eq(host_link.host(0, LOCALHOST), OK)
	host_link.setup.set_player_count(3)
	host_link.setup.set_team(0, 1)
	host_link.setup.set_team(1, 2)
	_host_lobby = SkirmishLobby.new()
	add_child_autofree(_host_lobby)
	_host_lobby.attach(host_link)
	var join_link := LobbyLink.new("build")
	_join_lobby = SkirmishLobby.new()
	add_child_autofree(_join_lobby)
	_join_lobby.attach(join_link)


func after_each() -> void:
	for lobby: SkirmishLobby in [_host_lobby, _join_lobby]:
		if lobby.link != null:
			lobby.link.close()
			lobby.link.close_transport()


func _join() -> void:
	assert_eq(_join_lobby.link.join(LOCALHOST, _host_lobby.link.lobby_port()), OK)


func _until(a_done: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(WAIT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if a_done.call():
			return true
		await get_tree().process_frame
	return false


func _control(a_lobby: SkirmishLobby, a_name: String) -> Control:
	return a_lobby.find_child(a_name, true, false) as Control


func _open_slot(a_slot: int) -> void:
	(_control(_host_lobby, "Open%d" % (a_slot + 1)) as CheckBox).button_pressed = true


func test_a_joiner_waits_on_the_host_then_is_seated_in_the_open_slot() -> void:
	_open_slot(1)
	_join()
	assert_true(await _until(func() -> bool: return _join_lobby.setup.slot_of(2) == 1))
	assert_eq((_control(_join_lobby, "Rows").get_child(6) as Label).text, "You")


func test_play_is_the_hosts_and_waits_for_every_open_slot() -> void:
	_open_slot(1)
	var play: Button = _control(_host_lobby, "Play") as Button
	assert_true(play.disabled, "slot 2 is open and empty")
	_join()
	assert_true(await _until(func() -> bool: return not play.disabled))
	assert_false(_control(_join_lobby, "Play").visible, "a joiner has no Play")


func test_a_joiner_edits_nothing_but_may_take_a_free_open_slot() -> void:
	_open_slot(1)
	_open_slot(2)
	_join()
	assert_true(await _until(func() -> bool: return _join_lobby.setup.slot_of(2) == 1))
	assert_true((_control(_join_lobby, "Faction1") as OptionButton).disabled)
	assert_true((_control(_join_lobby, "PlayerCount") as OptionButton).disabled)
	var take: Button = _control(_join_lobby, "Take3") as Button
	assert_not_null(take)
	assert_false(take.disabled)
	take.pressed.emit()
	assert_true(await _until(func() -> bool: return _host_lobby.setup.slot_of(2) == 2))
