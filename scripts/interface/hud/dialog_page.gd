@tool
class_name DialogPage
extends VBoxContainer

## One page of pop-up copy, authored as its own scene under `scenes/dialogs/`.
##
## The point is REUSE. A tutorial explains the same controls the help menu explains, and a
## mission may want to repeat a briefing; keeping the copy in a scene means one file to write
## and one file to fix a typo in, referenced by an EventShowDialog, by the help book, or by
## both. Copy authored inline on each event node could not be shared and drifted the moment
## anyone edited one copy.
##
## A page is a Control, not a Resource, so it can grow past three strings: drop extra child
## Controls (a diagram, a key-bindings grid) into the scene and they lay out under the body
## text. The exported strings are just the common case, rendered by the labels this builds in
## _ready — so the usual page is "make a scene, fill in three fields in the inspector".
##
## Specifically a VBoxContainer, which is what lets the dialog window size itself: a container
## reports a minimum size derived from its children, so the wrapped height of the body text
## propagates out through the panel. A plain Control reports only its own custom_minimum_size,
## and the window had to guess a fixed height that was wrong for every page.
##
## Pages are instantiated by ScenarioDialogView when it displays them, and freed when it
## moves on. Nothing else should hold one: they are content, not state.

#region Properties
## Heading. Empty draws no title row. Supports {{ action }} placeholders (see InputPrompt).
@export var title: String = "":
	set(value):
		title = value
		_refresh()

## The copy. BBCode is enabled, so [b], [i] and [color] work.
##
## Write control prompts as `{{ action_name }}` rather than naming a key — "hold and drag
## {{ world_select }}" renders as "hold and drag Left Mouse Button", from whatever
## that action is bound to right now. The swap is plain text, so wrap the placeholder in
## markup yourself if you want the key to stand out. See InputPrompt.
@export_multiline var body: String = "":
	set(value):
		body = value
		_refresh()

## Label for the button that dismisses this page when an event raises it. Ignored in the
## help book, which is closed with the help button rather than acknowledged. Also supports
## {{ action }} placeholders; read through resolved_acknowledge_text().
@export var acknowledge_text: String = "Continue"

## Width the page lays out to; the window sizes its panel around it, and the body text wraps
## within it. Height is never specified — it comes from however much text there is.
##
## Per page rather than global so a terse confirmation can be narrow and a control reference
## wide, but a consistent value across a scenario's pages keeps the window from resizing
## between beats.
@export var content_width: float = 520.0
#endregion

#region Constants
const TITLE_COLOR: Color = Color(1.0, 0.85, 0.15)
const TITLE_FONT_SIZE: int = 22
#endregion

#region Nodes
var _title_label: Label
var _body_label: RichTextLabel
#endregion


#region Lifecycle
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Width only. The height is whatever the stacked children need, which is the whole point of
	# being a container.
	custom_minimum_size = Vector2(content_width, 0.0)
	add_theme_constant_override("separation", 10)
	_build()
	_refresh()


## Build the title/body labels and move them ABOVE any authored children, so a page that adds
## its own content still reads top-to-bottom: heading, copy, extras.
func _build() -> void:
	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.add_theme_color_override("font_color", TITLE_COLOR)
	_title_label.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	add_child(_title_label)
	move_child(_title_label, 0)

	_body_label = RichTextLabel.new()
	_body_label.name = "Body"
	_body_label.bbcode_enabled = true
	# fit_content is what makes the label report its WRAPPED height as a minimum size, which is
	# what the panel ultimately grows to. Without it the label claims no height and the window
	# falls back to whatever fixed guess it was given.
	_body_label.fit_content = true
	_body_label.scroll_active = false
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.custom_minimum_size = Vector2(content_width, 0.0)
	_body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body_label)
	move_child(_body_label, 1)


#endregion


#region Public API
## The button label with its {{ action }} placeholders resolved. Plain text — the button is
## a Button, which does not parse BBCode.
func resolved_acknowledge_text() -> String:
	return InputPrompt.format(acknowledge_text)


#endregion


#region Internal
## Push the exported strings onto the labels, resolving control placeholders on the way.
##
## Resolution happens HERE rather than at author time, so a page shows what the player would
## actually press today: the labels get the resolved text while `title` / `body` keep the
## placeholders they were written with.
##
## Guarded because the setters run while the scene is still loading, before _ready has built
## anything.
func _refresh() -> void:
	if _title_label == null or _body_label == null:
		return
	var resolved_title: String = InputPrompt.format(title)
	_title_label.text = resolved_title
	_title_label.visible = not resolved_title.is_empty()
	var resolved_body: String = InputPrompt.format(body)
	_body_label.text = resolved_body
	_body_label.visible = not resolved_body.is_empty()
#endregion
