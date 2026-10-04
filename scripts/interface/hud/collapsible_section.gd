class_name CollapsibleSection
extends VBoxContainer

## A titled block of a readout popup that folds to its title: one per weapon, per projectile,
## per phase list and per phase (gdd/systems/ux/ui/piece-readouts.md §Long readouts fold). The
## one template every foldable list in a readout is.
##
## Whether a section is open is the reader's choice, and it outlives the section: a popup
## rebuilds its rows on every verbose toggle and every edit, and a fold the reader made must
## not spring open again each time. It is remembered by `key`.

const TITLE_FONT_SIZE: int = 13
const MINOR_FONT_SIZE: int = 11
const TITLE_COLOR: Color = Color(0.95, 0.85, 0.55)
## How far a section's body sits in from its title, so nesting reads at a glance.
const INDENT: int = 12
const OPEN_MARK: String = "▾ "
const CLOSED_MARK: String = "▸ "

## key -> whether the reader left that section open. State the reader made, so it is kept
## across the rebuilds that recreate the section's nodes.
static var _open_by_key: Dictionary = {}

## Where the section's rows go.
var body: VBoxContainer
## The title row, for controls a caller adds beside the title (a phase's move and remove).
var header: HBoxContainer

var _key: String
var _title: String
var _toggle: Button
var _indent: MarginContainer


## A section titled `a_title`, open unless the reader has folded it — or, never having touched
## it, unless `a_is_open_by_default` is false.
static func make(
	a_key: String, a_title: String, a_is_open_by_default: bool, a_is_minor: bool = false
) -> CollapsibleSection:
	var section := CollapsibleSection.new()
	section._key = a_key
	section._title = a_title
	section._build(bool(_open_by_key.get(a_key, a_is_open_by_default)), a_is_minor)
	return section


func is_open() -> bool:
	return _indent.visible


func set_open(a_is_open: bool) -> void:
	_indent.visible = a_is_open
	_toggle.text = (OPEN_MARK if a_is_open else CLOSED_MARK) + _title
	_open_by_key[_key] = a_is_open


func _build(a_is_open: bool, a_is_minor: bool) -> void:
	add_theme_constant_override("separation", 2)
	header = HBoxContainer.new()
	_toggle = Button.new()
	_toggle.flat = true
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toggle.add_theme_font_size_override(
		"font_size", MINOR_FONT_SIZE if a_is_minor else TITLE_FONT_SIZE
	)
	_toggle.add_theme_color_override("font_color", TITLE_COLOR)
	_toggle.pressed.connect(func() -> void: set_open(not is_open()))
	header.add_child(_toggle)
	add_child(header)
	_indent = MarginContainer.new()
	_indent.add_theme_constant_override("margin_left", INDENT)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	_indent.add_child(body)
	add_child(_indent)
	set_open(a_is_open)
