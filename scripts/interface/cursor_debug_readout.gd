class_name CursorDebugReadout
extends Label

## A DIAGNOSTIC, not a feature. Debug-view readout of every coordinate the custom
## mouse cursor depends on, so the "cursor goes plain outside a box in the middle of the
## screen" report can be turned into numbers.
##
## It exists because the cursor is the one part of this game that cannot be observed from
## here: `--headless` has no cursor, and `--write-movie` renders the VIEWPORT, which the OS
## cursor is not part of. So the machine that can see it has to report what it sees.
##
## What the numbers are for. The project renders a 1920x1080 viewport (`window/stretch/mode
## = "canvas_items"`) into an EXCLUSIVE FULLSCREEN window (`window/size/mode = 4`) whose real
## size is the display's. Whenever those two disagree — a non-16:9 display letterboxing the
## stretch, a Retina backing scale, a fullscreen transition the window never re-measured —
## there is a rectangle where the two coordinate spaces line up and a region outside it where
## they do not. A custom cursor applied over one space and a pointer moving through the other
## is exactly the shape of the reported bug.
##
## HOW TO USE IT: toggle the debug view on, walk the pointer to where the cursor stops being the
## game's art, and read off both position lines at that boundary.
##   * the two positions AGREE at the boundary        -> not a coordinate mismatch; the OS is
##                                                       dropping the cursor, and the
##                                                       re-assert policy is the problem
##   * they DIVERGE, or `viewport` stops changing     -> a coordinate mismatch, and the
##                                                       boundary's numbers say which pair
##
## Delete this file once the cursor is fixed. It is instrumentation with a question to
## answer, not a debug view worth keeping.


func _ready() -> void:
	# Above the world and outside the HUD's layout, like the other debug surfaces.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(16.0, 16.0)
	add_theme_color_override("font_color", Color(1.0, 0.95, 0.4))
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _process(_a_delta: float) -> void:
	visible = DebugMode.is_active()
	if visible:
		text = readout(get_viewport(), get_window())


## Built as a pure function of the two surfaces so it can be exercised without a running
## game — which is the only way any of this gets a test at all.
static func readout(viewport: Viewport, window: Window) -> String:
	var lines: Array[String] = []
	if viewport != null:
		lines.append(
			(
				"viewport  size %s   mouse %s"
				% [viewport.get_visible_rect().size, viewport.get_mouse_position()]
			)
		)
	lines.append(
		(
			"window    size %s   mouse %s"
			% [DisplayServer.window_get_size(), DisplayServer.mouse_get_position()]
		)
	)
	if window != null:
		lines.append(
			(
				"stretch   scale_size %s   scale_factor %s   mode %d   aspect %d"
				% [
					window.content_scale_size,
					window.content_scale_factor,
					window.content_scale_mode,
					window.content_scale_aspect
				]
			)
		)
	lines.append(
		(
			"screen    size %s   scale %s   dpi %d"
			% [
				DisplayServer.screen_get_size(),
				DisplayServer.screen_get_scale(),
				DisplayServer.screen_get_dpi()
			]
		)
	)
	return "\n".join(lines)
