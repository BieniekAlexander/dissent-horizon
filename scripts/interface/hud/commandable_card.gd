class_name CommandableCard
extends Control

## A small card representing a commandable (a live unit or a unit being trained).
## Renders a letter "icon" plus a stack of thin status bars along the bottom.
##
## Kept intentionally flexible: the icon and each bar are addressed by a string
## key, so future additions (energy bar, garrison count, status-effect badges,
## and eventually a real unit sprite in place of the letter) just add another
## keyed element without reworking the layout.
##
## Two bind modes drive what the card shows and self-updates each frame:
##   * bind_existing(commandable) — a live unit: red HP bar.
##   * bind_training(producer, i)  — a queued/training unit: blue progress bar.

const CARD_SIZE: Vector2 = Vector2(48, 48)
const BAR_HEIGHT: float = 5.0
const ICON_FONT_SIZE: int = 22

const HP_COLOR: Color = Color(0.85, 0.2, 0.2)          ## red
const TRAINING_COLOR: Color = Color(0.25, 0.55, 0.95)  ## blue
const BAR_BG_COLOR: Color = Color(0.0, 0.0, 0.0, 0.6)

var _icon: Label
var _bars_box: VBoxContainer
var _bar_fills: Dictionary = {}  # key -> fill ColorRect

## What this card represents (exactly one is set). See the bind_* methods.
var _commandable: Commandable = null
var _producer: Commandable = null
var _job_index: int = -1

#region Lifecycle
func _ready() -> void:
	custom_minimum_size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.1, 0.5)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_icon = Label.new()
	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_icon.add_theme_font_size_override("font_size", ICON_FONT_SIZE)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)

	# Bars hug the bottom edge and grow upward as more are added.
	_bars_box = VBoxContainer.new()
	_bars_box.add_theme_constant_override("separation", 1)
	_bars_box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bars_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bars_box)

func _process(_delta: float) -> void:
	if _commandable != null:
		_refresh_existing()
	elif _producer != null:
		_refresh_training()
#endregion

#region Binding
## Represent a live unit: icon from its scene, red HP bar.
func bind_existing(commandable: Commandable) -> void:
	_commandable = commandable
	_producer = null
	_job_index = -1
	set_icon(_letter(commandable.scene_file_path))
	_refresh_existing()

## Represent the queued/training unit at `job_index` of `producer`'s queue:
## icon from its scene, blue training-progress bar. The card is clickable — a left
## click cancels this job (removing it from the queue and refunding its cost).
func bind_training(producer: Commandable, job_index: int) -> void:
	_producer = producer
	_job_index = job_index
	_commandable = null
	# Training cards accept clicks to cancel; live-unit cards stay non-interactive.
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Click to cancel (refunds cost)"
	if producer.production != null and job_index < producer.production.job_count():
		set_icon(_letter(producer.production.job_scene(job_index).resource_path))
	_refresh_training()

## Cancel this card's training job on left click. InfoView rebuilds the detail cards
## when the queue changes, so the freed/renumbered cards follow automatically.
func _gui_input(event: InputEvent) -> void:
	if _producer == null:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if is_instance_valid(_producer) and _producer.production != null:
			_producer.production.cancel(_job_index)
			accept_event()
#endregion

#region Display API
## Sets the icon text (for now, the capitalized first letter of a scene name).
func set_icon(text: String) -> void:
	if _icon != null:
		_icon.text = text

## Creates or updates a bottom bar identified by `key`, filled to `ratio` (0..1).
func set_bar(key: String, ratio: float, color: Color) -> void:
	var fill: ColorRect = _bar_fills.get(key)
	if fill == null:
		fill = _add_bar(key)
	fill.color = color
	fill.anchor_right = clampf(ratio, 0.0, 1.0)

## Removes a previously-added bar.
func remove_bar(key: String) -> void:
	var fill: ColorRect = _bar_fills.get(key)
	if fill != null:
		fill.get_parent().queue_free()
		_bar_fills.erase(key)
#endregion

#region Private helpers
func _refresh_existing() -> void:
	if not is_instance_valid(_commandable):
		return
	# Direct node lookup rather than the @onready `defense` field, which can read
	# null depending on how the entity entered the tree.
	var defense: Defense = _commandable.get_node_or_null("Defense") as Defense
	if defense != null and defense.hp_max > 0.0:
		set_bar("hp", defense.hp / defense.hp_max, HP_COLOR)

func _refresh_training() -> void:
	if not is_instance_valid(_producer) or _producer.production == null:
		return
	# Guard: the queue may have shrunk (unit finished) before our owner rebuilds.
	if _job_index >= _producer.production.job_count():
		return
	set_bar("training", _producer.production.job_progress(_job_index), TRAINING_COLOR)

## Adds an empty bar row for `key` and returns its fill ColorRect.
func _add_bar(key: String) -> ColorRect:
	var row := Control.new()
	row.custom_minimum_size = Vector2(0, BAR_HEIGHT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := ColorRect.new()
	bg.color = BAR_BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bg)

	var fill := ColorRect.new()
	# Left-anchored; anchor_right is the fill fraction so the bar scales with width.
	fill.anchor_left = 0.0
	fill.anchor_top = 0.0
	fill.anchor_bottom = 1.0
	fill.anchor_right = 0.0
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(fill)

	_bars_box.add_child(row)
	_bar_fills[key] = fill
	return fill

## Capitalized first letter of a scene's file name, e.g. ".../warlord.tscn" -> "W".
static func _letter(scene_path: String) -> String:
	var base: String = scene_path.get_file().get_basename()
	return base.substr(0, 1).to_upper() if not base.is_empty() else "?"
#endregion
