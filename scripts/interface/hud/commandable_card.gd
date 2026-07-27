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
## Three bind modes drive what the card shows and self-updates each frame:
##   * bind_existing(commandable) — a live unit: red HP bar.
##   * bind_training(producer, i)  — a queued/training unit: blue progress bar.
##   * bind_purchase(transaction, queue) — a purchase still waiting on the commander's
##     global production queue: amber bar showing how close the commander is to
##     affording it.
##
## A live-unit card bound via bind_existing(commandable, true) is clickable and emits
## `activated(commandable, shift_held)` on left click; the owner (InfoView) decides what
## that means for its context (re-select the unit, or evacuate a garrison occupant).
##
## A clickable card raises its mouse_filter and marks itself CURSOR_POINTING_HAND, which
## carries the game's own pointer art (RTSController._register_hud_cursor). Asking for a shape
## with no art registered is what drops the cursor to the OS default — see
## gdd/systems/ux/ui/hud-layout.md.

## Emitted when a clickable live-unit card is left-clicked. `shift_held` is true when
## Shift was down. Not emitted for training cards (those cancel their job directly).
signal activated(commandable: Commandable, shift_held: bool)

## A RIGHT click on a card bound to a queued PURCHASE: the player is selecting the unit that
## purchase will produce, so they can give it orders before it exists. `all_of_type` carries
## the broaden modifier — take every pending purchase of the same piece, not just this one.
##
## A signal rather than a direct call because the card knows nothing of the controller; the
## rail that built it wires this to `RTSController.select_pending`.
signal pending_selected(transactions: Array, additive: bool, all_of_type: bool)

## A RIGHT click on a card bound to a live Commandable. The info panel spends it on a GARRISON
## OCCUPANT: selecting one lets the player give it orders it carries out on coming out, where
## the LEFT click throws it out of the vehicle immediately.
signal select_requested(commandable: Commandable, additive: bool)

const CARD_SIZE: Vector2 = Vector2(48, 48)
const BAR_HEIGHT: float = 5.0
const ICON_FONT_SIZE: int = 22
const CORNER_FONT_SIZE: int = 11
## Run counts and ring marks read as annotation, not as state, so they stay neutral —
## the coloured corner is the blocker glyph's, and only one thing per card should shout.
const BADGE_COLOR: Color = Color(0.86, 0.87, 0.86)
## The info panel's backdrop is light enough for a near-black card to read against it. A
## card drawn on a DARK panel (the production rail) needs a lighter body or it disappears
## into it — see set_background_color.
const DEFAULT_BACKGROUND_COLOR: Color = Color(0.1, 0.1, 0.1, 0.5)

const HP_COLOR: Color = Color(0.85, 0.2, 0.2)          ## red
const TRAINING_COLOR: Color = Color(0.25, 0.55, 0.95)  ## blue
const PURCHASE_COLOR: Color = Color(0.9, 0.7, 0.2)     ## amber — saving up for it
const FUNDED_COLOR: Color = Color(0.3, 0.8, 0.4)       ## green — paid for, waiting to start
const BAR_BG_COLOR: Color = Color(0.0, 0.0, 0.0, 0.6)

## The border a SELECTED pending purchase wears. Green because that is what the rail already
## uses for "paid for" (FUNDED_COLOR) and a selected phantom is the same kind of promise — a
## thing you have committed to that is not here yet.
const PENDING_SELECTED_BORDER: Color = Color(0.35, 0.9, 0.45)
const PENDING_SELECTED_BORDER_WIDTH: float = 2.0

var _background: ColorRect
var _icon: Label
var _bars_box: VBoxContainer
var _bar_fills: Dictionary = {}  # key -> fill ColorRect
## Two corner overlays, both created lazily because most cards use neither: a BADGE in the
## top-right (a ×N run count, or the ring's next-up mark) and a GLYPH in the top-left (why
## a purchase is stuck). They are separate elements rather than one composite string
## because they answer unrelated questions and can appear independently.
var _badge: Label = null
var _glyph: Label = null

## What this card represents (exactly one is set). See the bind_* methods.
var _commandable: Commandable = null
var _producer: Commandable = null
var _job_index: int = -1
var _transaction: PurchaseTransaction = null
## Every transaction a COLLAPSED run stands for, or empty for a single-purchase card. Kept so
## a right click can select the whole run the player is looking at rather than only its head.
var _group: Array = []
## The green selected-border overlay, created on first use — most cards never need one.
var _pending_border: ReferenceRect = null
var _queue: ProductionQueue = null
## Which transaction a click cancels. The same as `_transaction` for a single-purchase card,
## but the LAST of the run for a collapsed group — see bind_purchase_group.
var _cancel_target: PurchaseTransaction = null

## Whether the mouse is currently over this card. Only meaningful for a training-bound
## card today — the rally indicator (RTSController._update_rally_indicator, via
## InfoView.hovered_training_target) reads it to preview that specific queued unit's own
## orders instead of the head-of-queue rally. Tracked here rather than with a
## VerboseTooltipButton-style popup because this hover means "show something in the
## world", not "show more text".
var _hovering: bool = false

#region Lifecycle
func _ready() -> void:
	custom_minimum_size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	mouse_entered.connect(func(): _hovering = true)
	mouse_exited.connect(func(): _hovering = false)

	_background = ColorRect.new()
	_background.color = DEFAULT_BACKGROUND_COLOR
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)

	_icon = Label.new()
	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_icon.add_theme_font_size_override("font_size", ICON_FONT_SIZE)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)

	# Bars hug the bottom edge and grow upward as more are added. PRESET_BOTTOM_WIDE pins the
	# box to the bottom edge with zero height, and the default grow direction is END — so the
	# box expanded DOWNWARD and every bar was drawn outside the card, under its bottom edge.
	# Growing from the BEGIN edge is what the line above always claimed to do.
	_bars_box = VBoxContainer.new()
	_bars_box.add_theme_constant_override("separation", 1)
	_bars_box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bars_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bars_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bars_box)

func _process(_a_delta: float) -> void:
	if _commandable != null:
		_refresh_existing()
	elif _producer != null:
		_refresh_training()
	elif _transaction != null:
		_refresh_purchase()
#endregion

#region Binding
## Represent a live unit: icon from its scene, red HP bar. When `clickable` is true the
## card accepts left clicks and emits `activated(commandable, shift_held)` — used by the
## summary (re-select) and garrison-occupant (evacuate) card lists.
func bind_existing(a_commandable: Commandable, a_clickable: bool = false) -> void:
	_commandable = a_commandable
	_producer = null
	_job_index = -1
	if a_clickable:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	set_icon(_letter(a_commandable.scene_file_path))
	_refresh_existing()

## Represent the queued/training unit at `job_index` of `producer`'s queue:
## icon from its scene, blue training-progress bar. The card is clickable — a left
## click cancels this job (removing it from the queue and refunding its cost).
func bind_training(a_producer: Commandable, a_job_index: int) -> void:
	_producer = a_producer
	_job_index = a_job_index
	_commandable = null
	# Training cards accept clicks to cancel; live-unit cards stay non-interactive.
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Click to cancel (refunds cost)"
	if a_producer.production != null and a_job_index < a_producer.production.job_count():
		set_icon(_letter(a_producer.production.job_scene(a_job_index).resource_path))
	_refresh_training()

## Represent a purchase still queued on the commander's global production queue: icon
## from the purchased scene, amber bar showing progress toward affording it (green once
## funded and merely waiting on a builder). Clickable — a left click cancels the
## purchase, refunding anything already reserved.
func bind_purchase(a_transaction: PurchaseTransaction, a_queue: ProductionQueue) -> void:
	_transaction = a_transaction
	_queue = a_queue
	_commandable = null
	_producer = null
	_job_index = -1
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "%s — %d energy\nClick to cancel%s" % [
		a_transaction.type,
		a_transaction.energy_cost if a_transaction.energy_cost > 0 else a_transaction.dominion_cost,
		"\nStanding order — re-issues after every other purchase" if a_transaction.standing else "",
	]
	# The piece ID is the identity and is always present; the scene path is only preferred
	# because it is what the other two bind modes have to work from. A purchase whose tool
	# carries no scene used to fall through and draw a BLANK chip, which is worse than a
	# wrong letter — an unlabelled card says nothing at all.
	if a_transaction.tool != null and a_transaction.tool.packed_scene != null:
		set_icon(_letter(a_transaction.tool.packed_scene.resource_path))
	else:
		set_icon(_first_letter(String(a_transaction.type)))
	_cancel_target = a_transaction
	_refresh_purchase()

## Represent a RUN of identical queued purchases as one chip, badged ×N.
##
## Collapsing runs is what keeps the production rail readable: ten queued Recruits are one
## chip saying ×10, not ten chips. Only ADJACENT entries of the same type are ever passed
## here, because the queue's order is meaningful — collapsing across a gap would claim a
## dispatch order the queue does not have.
##
## The card binds to the run's FIRST entry, so its fill bar tracks the one that will be paid
## for next; clicking cancels the LAST, which makes a click undo the most recent of the
## repeated presses that built the run.
func bind_purchase_group(a_transactions: Array, a_queue: ProductionQueue) -> void:
	if a_transactions.is_empty():
		return
	bind_purchase(a_transactions.front() as PurchaseTransaction, a_queue)
	_group = a_transactions.duplicate()
	if a_transactions.size() > 1:
		_cancel_target = a_transactions.back() as PurchaseTransaction
		set_badge("×%d" % a_transactions.size(), BADGE_COLOR)
		tooltip_text = "%s ×%d\nClick to cancel one" % [
			(a_transactions.front() as PurchaseTransaction).type, a_transactions.size()
		]

#region Corner overlays
## Sets the top-right badge — a run count, or the standing ring's next-up mark.
func set_badge(a_text: String, a_color: Color) -> void:
	if _badge == null:
		_badge = _add_corner_label(HORIZONTAL_ALIGNMENT_RIGHT)
	_badge.text = a_text
	_badge.add_theme_color_override("font_color", a_color)

## Sets the top-left glyph — what a queued purchase is waiting on. Shown ONLY when a
## purchase is actually blocked (see ProductionRail): a glyph on every chip is decoration, a
## glyph on the stuck one is information.
func set_glyph(a_text: String, a_color: Color) -> void:
	if _glyph == null:
		_glyph = _add_corner_label(HORIZONTAL_ALIGNMENT_LEFT)
	_glyph.text = a_text
	_glyph.add_theme_color_override("font_color", a_color)

func _add_corner_label(a_alignment: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	label.horizontal_alignment = a_alignment
	label.add_theme_font_size_override("font_size", CORNER_FONT_SIZE)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label
#endregion

## Repaint the card body, for a card drawn on a surface the default was not chosen against.
func set_background_color(a_color: Color) -> void:
	if _background != null:
		_background.color = a_color

## Shrink (or grow) the card from the default CARD_SIZE. The production rail runs smaller
## than the info panel does, because it is on screen permanently and the info panel is not.
func set_card_size(a_size: Vector2) -> void:
	custom_minimum_size = a_size
	size = a_size
	if _icon != null:
		_icon.add_theme_font_size_override("font_size", roundi(a_size.y * 0.46))

## Left click handling. A training card cancels its job; a clickable live-unit card
## emits `activated` so its owner can act (re-select / evacuate). InfoView rebuilds the
## cards when the underlying set changes, so freed/renumbered cards follow automatically.
##
## BOTH the press and the release are consumed (accept_event on each). The world-selection
## handler in RTSController fires on the button RELEASE (is_action_released → set_selection),
## so leaving the release unconsumed would let a card click also trigger a world select/
## deselect — e.g. clicking an occupant card would evacuate AND then clear the selection.
func _gui_input(a_event: InputEvent) -> void:
	var mouse_event := a_event as InputEventMouseButton
	# RIGHT click on a queued purchase SELECTS the phantom it will produce. Consumed whole, the
	# same way the left click is, so it never also reaches the world as a command.
	if mouse_event != null and mouse_event.button_index == MOUSE_BUTTON_RIGHT \
			and _transaction != null:
		accept_event()
		if mouse_event.pressed:
			pending_selected.emit(
				_pending_group(),
				Input.is_action_pressed(RTSController.MODIFIER_ADDITIVE),
				Input.is_action_pressed(RTSController.MODIFIER_BROADEN))
		return
	# RIGHT click on a TRAINING job's card selects the unit being built — the same phantom
	# selection a queued purchase gets, for the one that has left the queue and is on the
	# producer's own bench.
	if mouse_event != null and mouse_event.button_index == MOUSE_BUTTON_RIGHT \
			and _producer != null and is_instance_valid(_producer) and _producer.production != null:
		accept_event()
		if mouse_event.pressed:
			var transaction: PurchaseTransaction = _producer.production.job_transaction(_job_index)
			if transaction != null:
				pending_selected.emit(
					[transaction],
					Input.is_action_pressed(RTSController.MODIFIER_ADDITIVE),
					Input.is_action_pressed(RTSController.MODIFIER_BROADEN))
		return
	# RIGHT click on a live unit's card asks for it to be SELECTED. Whether anything listens is
	# the binder's business — the info panel spends it on garrison occupants and nothing else.
	if mouse_event != null and mouse_event.button_index == MOUSE_BUTTON_RIGHT \
			and _commandable != null and is_instance_valid(_commandable):
		accept_event()
		if mouse_event.pressed:
			select_requested.emit(
				_commandable, Input.is_action_pressed(RTSController.MODIFIER_ADDITIVE))
		return
	if not (a_event is InputEventMouseButton and a_event.button_index == MOUSE_BUTTON_LEFT):
		return
	# Consume the whole click (press + release) so it never reaches RTSController's
	# selection input. Act only on the press.
	accept_event()
	if not a_event.pressed:
		return
	if _producer != null:
		if is_instance_valid(_producer) and _producer.production != null:
			_producer.production.cancel(_job_index)
	elif _transaction != null:
		if _queue != null:
			_queue.cancel(_cancel_target if _cancel_target != null else _transaction)
	elif _commandable != null and is_instance_valid(_commandable):
		activated.emit(_commandable, (a_event as InputEventMouseButton).shift_pressed)
#endregion

## Every transaction this card stands for — the whole collapsed run, not just its head. A
## card showing "×5" is five purchases, and selecting it selects all five: the run is
## collapsed for display, and the player is pointing at what they can see.
func purchase_group() -> Array:
	return _group.duplicate() if not _group.is_empty() else [_transaction]


func _pending_group() -> Array:
	return purchase_group()


## Draw (or clear) the green border that says this card's phantom is selected.
func set_pending_selected(a_is_selected: bool) -> void:
	if _background == null:
		return
	if _pending_border == null:
		_pending_border = ReferenceRect.new()
		_pending_border.border_color = PENDING_SELECTED_BORDER
		_pending_border.border_width = PENDING_SELECTED_BORDER_WIDTH
		# editor_only defaults TRUE, which draws nothing in a running game.
		_pending_border.editor_only = false
		_pending_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_pending_border)
		# ANCHORED AFTER add_child, and offsets zeroed by hand. A preset applied to a parentless
		# Control has no rect to resolve against, so the border came out a zero-size box in the
		# corner — invisible, while every other sign said it was there. Same trap as the status
		# bars that drew below their card (CLAUDE.md §Seeing the HUD without a screen).
		_pending_border.set_anchors_preset(Control.PRESET_FULL_RECT, true)
		_pending_border.offset_left = 0.0
		_pending_border.offset_top = 0.0
		_pending_border.offset_right = 0.0
		_pending_border.offset_bottom = 0.0
	_pending_border.visible = a_is_selected

#region Hover state
## True while this card is bound to a queued unit (bind_training) and the mouse is over
## it. See _hovering.
func is_hovered_training() -> bool:
	return _hovering and _producer != null

## True while this card is bound to a queued PURCHASE (bind_purchase / bind_purchase_group)
## and the mouse is over it. Read by ProductionRail so the world can ring the structures that
## could fulfil it — the same "this hover means show something in the world" use the training
## case already has, pointed at a purchase instead of at a job.
func is_hovered_purchase() -> bool:
	return _hovering and _transaction != null

## The purchase this card stands for, or null. For a collapsed run this is the run's FIRST
## entry — the one that will be dispatched next, and so the one whose eligible producers are
## the ones worth marking.
func hovered_transaction() -> PurchaseTransaction:
	return _transaction

## The producer/job_index this card is bound to via bind_training, or null/-1 otherwise.
func training_producer() -> Commandable:
	return _producer

func training_job_index() -> int:
	return _job_index
#endregion

#region Display API
## Sets the icon text (for now, the capitalized first letter of a scene name).
func set_icon(a_text: String) -> void:
	if _icon != null:
		_icon.text = a_text

## Creates or updates a bottom bar identified by `key`, filled to `ratio` (0..1).
func set_bar(a_key: String, a_ratio: float, a_color: Color) -> void:
	var fill: ColorRect = _bar_fills.get(a_key)
	if fill == null:
		fill = _add_bar(a_key)
	fill.color = a_color
	fill.anchor_right = clampf(a_ratio, 0.0, 1.0)

## Removes a previously-added bar.
func remove_bar(a_key: String) -> void:
	var fill: ColorRect = _bar_fills.get(a_key)
	if fill != null:
		fill.get_parent().queue_free()
		_bar_fills.erase(a_key)
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

## Fill fraction is how much of the price the commander has banked, so a queued purchase
## visibly fills as energy comes in. A funded one (paid for, waiting on its builder) shows a
## full green bar instead.
func _refresh_purchase() -> void:
	if _transaction == null or _transaction.commander == null:
		return
	if _transaction.is_funded():
		set_bar("purchase", 1.0, FUNDED_COLOR)
		return
	var cost: int = maxi(_transaction.energy_cost, _transaction.dominion_cost)
	var banked: int = _transaction.commander.energy if _transaction.energy_cost > 0 \
		else _transaction.commander.dominion
	set_bar("purchase", 1.0 if cost <= 0 else float(banked) / float(cost), PURCHASE_COLOR)

## Adds an empty bar row for `key` and returns its fill ColorRect.
func _add_bar(a_key: String) -> ColorRect:
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
	_bar_fills[a_key] = fill
	return fill

## Capitalized first letter of a scene's file name, e.g. ".../warlord.tscn" -> "W".
static func _letter(scene_path: String) -> String:
	return _first_letter(scene_path.get_file().get_basename())

## Capitalized first letter of any identifier, or "?" when there isn't one.
static func _first_letter(text: String) -> String:
	return text.substr(0, 1).to_upper() if not text.is_empty() else "?"
#endregion
