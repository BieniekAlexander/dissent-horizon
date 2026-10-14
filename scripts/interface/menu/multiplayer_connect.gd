class_name MultiplayerConnect
extends VBoxContainer
## THE MULTIPLAYER PAGE: host a lobby on a port, or join one by address and port. Either opens a
## LobbyLink and hands it to the skirmish lobby, which runs the rest. Placeholder visuals, built
## in code. gdd/systems/ux/ui/menus.md §Multiplayer.

## A lobby is open — hosted, or dialled and waiting for the host's answer.
signal lobby_opened(a_link: LobbyLink)
## The Back button.
signal back_requested

## The port a lobby is hosted on and dialled at unless the player types another. Any free port
## would do; one fixed default is what lets two players agree on it without saying.
const DEFAULT_PORT: int = 47600
const MIN_PORT: int = 1024
const MAX_PORT: int = 65535
const DEFAULT_ADDRESS: String = "127.0.0.1"
const FIELD_WIDTH: float = 220.0

var _address: LineEdit
var _port: SpinBox
var _status: Label


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	var heading := Label.new()
	heading.text = "Multiplayer"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 26)
	add_child(heading)

	_address = LineEdit.new()
	_address.name = "Address"
	_address.text = DEFAULT_ADDRESS
	_address.placeholder_text = "Host's address"
	_port = SpinBox.new()
	_port.name = "Port"
	_port.min_value = MIN_PORT
	_port.max_value = MAX_PORT
	_port.value = DEFAULT_PORT
	add_child(_field("Address", _address))
	add_child(_field("Port", _port))

	_status = Label.new()
	_status.name = "Status"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(420.0, 0.0)
	add_child(_status)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	buttons.add_child(_button("Back", func() -> void: back_requested.emit()))
	buttons.add_child(_button("Host", host))
	buttons.add_child(_button("Join", join))
	add_child(buttons)


## Host a lobby on the port field's port.
func host() -> void:
	var link := LobbyLink.new()
	var error: Error = link.host(int(_port.value))
	if error != OK:
		show_status("Could not host on port %d: %s." % [int(_port.value), error_string(error)])
		return
	show_status("")
	lobby_opened.emit(link)


## Join the lobby at the address and port fields.
func join() -> void:
	var link := LobbyLink.new()
	var error: Error = link.join(_address.text.strip_edges(), int(_port.value))
	if error != OK:
		show_status("Could not reach %s: %s." % [_address.text, error_string(error)])
		return
	show_status("")
	lobby_opened.emit(link)


## Why the last attempt, or the last lobby, ended — shown under the fields.
func show_status(a_text: String) -> void:
	_status.text = a_text


func _field(a_label: String, a_control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var label := Label.new()
	label.text = a_label
	label.custom_minimum_size = Vector2(80.0, 0.0)
	row.add_child(label)
	a_control.custom_minimum_size = Vector2(FIELD_WIDTH, 0.0)
	row.add_child(a_control)
	return row


func _button(a_text: String, a_on_pressed: Callable) -> Button:
	var button := Button.new()
	button.name = a_text
	button.text = a_text
	button.custom_minimum_size = Vector2(140.0, 44.0)
	button.pressed.connect(a_on_pressed)
	return button
