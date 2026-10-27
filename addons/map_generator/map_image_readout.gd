@tool
extends VBoxContainer

## The image tab's readout: a top-down picture of the drawing, one pixel a cell, as the last import
## or export drew it — held in memory only, never written to disk. Shown as large as the panel is
## wide, sharp at any size, with what lies under the pointer named beneath it: the drawing pixel,
## what each layer says there, and the issue that marks it. **Open larger** shows the same picture
## in a window of its own, zoomed with the wheel.

#region Constants
const EMPTY_TEXT: String = "Point at the readout to see a pixel's position and what is there."
const OPEN_TEXT: String = "Open larger…"
const WINDOW_TITLE: String = "Map image readout — wheel to zoom"
const WINDOW_SIZE := Vector2i(900, 900)
## Screen pixels a cell starts at in the window, and the most the wheel takes it to.
const WINDOW_ZOOM: int = 3
const MAX_ZOOM: int = 32
#endregion

#region Properties
var _texture: Texture2D = null
## Readout pixel -> what to say about it; returns "" for a pixel with nothing to say.
var _describe: Callable = Callable()
var _canvas: _Canvas
var _info: Label
var _open_button: Button
var _window: Window = null
var _window_canvas: _Canvas = null
var _window_info: Label = null
#endregion


## Draws the texture at a whole number of screen pixels a cell where it fits, and reports the
## readout pixel under the pointer. Fitted to its width, or at `zoom` when that is set.
class _Canvas:
	extends Control

	signal pointed(a_pixel: Vector2i)

	var texture: Texture2D = null
	## Screen pixels a cell; 0 fits the texture to the control's width.
	var zoom: int = 0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		resized.connect(_refit)

	func set_texture(a_texture: Texture2D) -> void:
		texture = a_texture
		_refit()
		queue_redraw()

	## The texture's rect on the control: fitted to the width, or at `zoom` — whole pixels a
	## cell whenever the space allows, so cell edges stay sharp.
	func drawn_rect() -> Rect2:
		if texture == null:
			return Rect2()
		var cells := Vector2(texture.get_size())
		var scale: float = float(zoom)
		if zoom <= 0:
			scale = size.x / cells.x
			if scale >= 1.0:
				scale = floorf(scale)
		return Rect2(((size - cells * scale) * 0.5).floor(), cells * scale)

	func _draw() -> void:
		if texture != null:
			draw_texture_rect(texture, drawn_rect(), false)

	func _gui_input(a_event: InputEvent) -> void:
		var motion := a_event as InputEventMouseMotion
		if motion == null or texture == null:
			return
		var rect: Rect2 = drawn_rect()
		if not rect.has_point(motion.position):
			pointed.emit(Vector2i(-1, -1))
			return
		var cells := Vector2(texture.get_size())
		pointed.emit(Vector2i(((motion.position - rect.position) / rect.size * cells).floor()))

	## Fitted, the control is as tall as the texture drawn across its width; zoomed, as big as
	## the zoomed texture, so a scroll container around it can scroll.
	func _refit() -> void:
		if texture == null:
			return
		var cells := Vector2(texture.get_size())
		if zoom > 0:
			custom_minimum_size = cells * zoom
		else:
			custom_minimum_size.y = size.x * cells.y / cells.x


func _ready() -> void:
	_canvas = _Canvas.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.pointed.connect(func(pixel: Vector2i) -> void: _info.text = _text_at(pixel))
	add_child(_canvas)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.text = EMPTY_TEXT
	add_child(_info)
	_open_button = Button.new()
	_open_button.text = OPEN_TEXT
	_open_button.disabled = true
	_open_button.pressed.connect(open_window)
	add_child(_open_button)


## Show `image`, or nothing for null; `describe` says what lies at a readout pixel.
func show_image(image: Image, describe: Callable) -> void:
	_texture = ImageTexture.create_from_image(image) if image != null else null
	_describe = describe
	_canvas.set_texture(_texture)
	_open_button.disabled = _texture == null
	_info.text = EMPTY_TEXT
	if _window_canvas != null:
		_window_canvas.set_texture(_texture)


func texture() -> Texture2D:
	return _texture


## What the readout says at `a_pixel`: its description, or the hint off the picture.
func _text_at(a_pixel: Vector2i) -> String:
	if a_pixel.x < 0 or not _describe.is_valid():
		return EMPTY_TEXT
	var text: String = _describe.call(a_pixel)
	return EMPTY_TEXT if text.is_empty() else text


## The readout in its own window, made on first use: zoomed with the wheel, scrolled when larger
## than the window, the pointed pixel named under it as in the panel.
func open_window() -> void:
	if _window == null:
		_window = Window.new()
		_window.title = WINDOW_TITLE
		_window.size = WINDOW_SIZE
		_window.close_requested.connect(_window.hide)
		var column := VBoxContainer.new()
		column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_window.add_child(column)
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.add_child(scroll)
		_window_canvas = _Canvas.new()
		_window_canvas.zoom = WINDOW_ZOOM
		_window_canvas.gui_input.connect(_zoom_on_wheel)
		_window_canvas.pointed.connect(
			func(pixel: Vector2i) -> void: _window_info.text = _text_at(pixel)
		)
		scroll.add_child(_window_canvas)
		_window_info = Label.new()
		_window_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_window_info.text = EMPTY_TEXT
		column.add_child(_window_info)
		add_child(_window)
	_window_canvas.set_texture(_texture)
	_window.popup_centered()


func _zoom_on_wheel(a_event: InputEvent) -> void:
	var button := a_event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	var step: int = 0
	if button.button_index == MOUSE_BUTTON_WHEEL_UP:
		step = 1
	elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		step = -1
	if step == 0:
		return
	_window_canvas.zoom = clampi(_window_canvas.zoom + step, 1, MAX_ZOOM)
	_window_canvas.set_texture(_texture)
	_window_canvas.accept_event()
