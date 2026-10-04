class_name CommandableCard
extends Control

## A small card representing a commandable (a live unit or a unit being trained).
##
## THE PICTURE FILLS THE CARD; TWO COLUMNS SIT OVER ITS RIGHT EDGE. The rightmost column is one
## vertical bar filling upward — the card's main figure. The column beside it is split in two:
## charge dials on top (ChargeDial, one per production queue, ability pool or slow weapon), a
## garrison bar beneath. The columns cover the picture rather than squeezing it, so every card's
## picture is the whole card. Layout and colours: gdd/systems/ux/ui/actor-cards.md.
##
## Three bind modes drive what the card shows and self-updates each frame:
##   * bind_existing(commandable) — a live unit: red HP column, its charge dials, and a green
##     garrison bar while it holds anyone.
##   * bind_training(producer, i)  — a queued/training unit: blue progress column.
##   * bind_purchase(transaction, queue) — a purchase still waiting on the commander's
##     global production queue: amber column showing how close the commander is to
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
## The column geometry, as fractions of the card's HEIGHT so a rail chip scales with it.
const MAIN_COLUMN_FRACTION: float = 0.1
const DIAL_FRACTION: float = 0.17
## How much of the dial column the dials get; the garrison bar has the rest.
const DIAL_ROW_FRACTION: float = 0.6
## The garrison bar is narrower than the dials above it, centred in their column.
const GARRISON_BAR_FRACTION: float = 0.5
const COLUMN_GAP: float = 1.0
const MIN_COLUMN_WIDTH: float = 2.0
const ICON_FONT_SIZE: int = 22
const CORNER_FONT_SIZE: int = 11
## Run counts and ring marks read as annotation, not as state, so they stay neutral —
## the coloured corner is the blocker glyph's, and only one thing per card should shout.
const BADGE_COLOR: Color = Color(0.86, 0.87, 0.86)
## The info panel's backdrop is light enough for a near-black card to read against it. A
## card drawn on a DARK panel (the production rail) needs a lighter body or it disappears
## into it — see set_background_color.
const DEFAULT_BACKGROUND_COLOR: Color = Color(0.1, 0.1, 0.1, 0.5)

const HP_COLOR: Color = Color(0.85, 0.2, 0.2)  ## red
## Green, the genre's garrison colour. Shares green with FUNDED_COLOR, which never meets it on
## one card — see actor-cards.md §Colour collisions.
const GARRISON_COLOR: Color = Color(0.3, 0.8, 0.4)
const TRAINING_COLOR: Color = Color(0.25, 0.55, 0.95)  ## blue
const PURCHASE_COLOR: Color = Color(0.9, 0.7, 0.2)  ## amber — saving up for it
const FUNDED_COLOR: Color = Color(0.3, 0.8, 0.4)  ## green — paid for, waiting to start
const BAR_BG_COLOR: Color = Color(0.0, 0.0, 0.0, 0.6)

## The border a SELECTED pending purchase wears. Green because that is what the rail already
## uses for "paid for" (FUNDED_COLOR) and a selected phantom is the same kind of promise — a
## thing you have committed to that is not here yet.
const PENDING_SELECTED_BORDER: Color = Color(0.35, 0.9, 0.45)
const PENDING_SELECTED_BORDER_WIDTH: float = 2.0

var _background: ColorRect
## The piece's picture (PieceIcons), drawn under the letter; empty when it has none, and then
## the letter is what identifies the card.
var _picture: TextureRect
var _icon: Label
## The main column (HP, or training / purchase progress) and the garrison bar: each a track
## with a fill anchored to its bottom (see _set_vertical_fill).
var _main_bar: Control
var _garrison_bar: Control
var _dial_box: VBoxContainer
## The dials, index-aligned with what each draws: an ability pool index (int) or a Weapon.
var _dials: Array[ChargeDial] = []
var _dial_sources: Array = []
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
## ProductionRail.hovered_training_target) reads it to preview that specific queued unit's own
## orders instead of the head-of-queue rally. Tracked here rather than with a
## VerboseTooltipButton-style popup because this hover means "show something in the
## world", not "show more text".
var _hovering: bool = false


#region Lifecycle
func _ready() -> void:
	custom_minimum_size = CARD_SIZE
	# Sized now rather than left to a parent container: a card that is never laid out (a
	# rail chip placed by hand, a test) would otherwise be 0×0, with its columns on top of
	# each other.
	size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	mouse_entered.connect(func(): _hovering = true)
	mouse_exited.connect(func(): _hovering = false)

	_background = ColorRect.new()
	_background.color = DEFAULT_BACKGROUND_COLOR
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)

	_picture = TextureRect.new()
	_picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_picture)

	_icon = Label.new()
	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_icon.add_theme_font_size_override("font_size", ICON_FONT_SIZE)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)

	_main_bar = _make_vertical_bar("MainBar")
	_main_bar.visible = false
	_garrison_bar = _make_vertical_bar("GarrisonBar")
	_garrison_bar.visible = false
	_dial_box = VBoxContainer.new()
	_dial_box.name = "Dials"
	_dial_box.add_theme_constant_override("separation", int(COLUMN_GAP))
	_dial_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dial_box)
	resized.connect(_layout)
	_layout()


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
	_show_piece(a_commandable.id, _letter(a_commandable.scene_file_path))
	_build_dials(a_commandable)
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
		# A RESEARCH job has no scene — nothing is spawned — so it is lettered by its id.
		var scene: PackedScene = a_producer.production.job_scene(a_job_index)
		var job_type: Variant = a_producer.production.job_type(a_job_index)
		var job_id: StringName = StringName(job_type) if job_type != null else &""
		_show_piece(
			job_id, _letter(scene.resource_path) if scene != null else _first_letter(String(job_id))
		)
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
	tooltip_text = (
		"%s — %d energy\nClick to cancel%s"
		% [
			a_transaction.type,
			(
				a_transaction.energy_cost
				if a_transaction.energy_cost > 0
				else a_transaction.dominion_cost
			),
			(
				"\nStanding order — re-issues after every other purchase"
				if a_transaction.standing
				else ""
			),
		]
	)
	# The piece ID is the identity and is always present; the scene path is only preferred
	# because it is what the other two bind modes have to work from. A purchase whose tool
	# carries no scene used to fall through and draw a BLANK chip, which is worse than a
	# wrong letter — an unlabelled card says nothing at all.
	_show_piece(
		a_transaction.type,
		(
			_letter(a_transaction.tool.packed_scene.resource_path)
			if a_transaction.tool != null and a_transaction.tool.packed_scene != null
			else _first_letter(String(a_transaction.type))
		)
	)
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
		tooltip_text = (
			"%s ×%d\nClick to cancel one"
			% [(a_transactions.front() as PurchaseTransaction).type, a_transactions.size()]
		)


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
	label.horizontal_alignment = a_alignment
	label.add_theme_font_size_override("font_size", CORNER_FONT_SIZE)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	# Over the PICTURE, not the full card: a badge across the columns would sit on the HP bar.
	_place(label, Rect2(Vector2.ZERO, Vector2(label_rect().size.x, label.get_minimum_size().y)))
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
	_layout()


## How many charge dials fit on a card `a_height` tall — the cap the spec importer warns
## past. Derived from the column geometry rather than set, so it follows any change to it.
static func dial_capacity(a_height: float) -> int:
	var dial: float = roundf(a_height * DIAL_FRACTION)
	var row: float = roundf(a_height * DIAL_ROW_FRACTION)
	return int((row + COLUMN_GAP) / (dial + COLUMN_GAP)) if dial > 0.0 else 0


## How wide the two columns are together, gaps included, on a card `a_height` tall — what a
## staggered row leaves showing of each card behind the first (StaggeredCardRow).
static func column_strip_width(a_height: float) -> float:
	var main_width: float = maxf(MIN_COLUMN_WIDTH, roundf(a_height * MAIN_COLUMN_FRACTION))
	return main_width + roundf(a_height * DIAL_FRACTION) + 2.0 * COLUMN_GAP


## The rect the letter and the corner labels keep to: everything left of the two columns, so
## text is never drawn under a bar. The PICTURE is not held to it — it fills the card.
func label_rect() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(maxf(0.0, size.x - column_strip_width(size.y)), size.y))


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
	if (
		mouse_event != null
		and mouse_event.button_index == MOUSE_BUTTON_RIGHT
		and _transaction != null
	):
		accept_event()
		if mouse_event.pressed:
			pending_selected.emit(
				_pending_group(),
				Input.is_action_pressed(RTSController.MODIFIER_ADDITIVE),
				Input.is_action_pressed(RTSController.MODIFIER_BROADEN)
			)
		return
	# RIGHT click on a TRAINING job's card selects the unit being built — the same phantom
	# selection a queued purchase gets, for the one that has left the queue and is on the
	# producer's own bench.
	if (
		mouse_event != null
		and mouse_event.button_index == MOUSE_BUTTON_RIGHT
		and _producer != null
		and is_instance_valid(_producer)
		and _producer.production != null
	):
		accept_event()
		if mouse_event.pressed:
			var transaction: PurchaseTransaction = _producer.production.job_transaction(_job_index)
			if transaction != null:
				pending_selected.emit(
					[transaction],
					Input.is_action_pressed(RTSController.MODIFIER_ADDITIVE),
					Input.is_action_pressed(RTSController.MODIFIER_BROADEN)
				)
		return
	# RIGHT click on a live unit's card asks for it to be SELECTED. Whether anything listens is
	# the binder's business — the info panel spends it on garrison occupants and nothing else.
	if (
		mouse_event != null
		and mouse_event.button_index == MOUSE_BUTTON_RIGHT
		and _commandable != null
		and is_instance_valid(_commandable)
	):
		accept_event()
		if mouse_event.pressed:
			select_requested.emit(
				_commandable, Input.is_action_pressed(RTSController.MODIFIER_ADDITIVE)
			)
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
## Sets the icon text, the capitalized first letter of a scene name — what a card shows for a
## piece with no picture (see _show_piece).
func set_icon(a_text: String) -> void:
	if _icon != null:
		_icon.text = a_text


## Draw piece `a_id` as its picture, or as `a_fallback_letter` when no picture has been made
## for it (a research job, a piece whose icon slot is unfilled).
func _show_piece(a_id: StringName, a_fallback_letter: String) -> void:
	var picture: Texture2D = PieceIcons.for_id(a_id)
	if _picture != null:
		_picture.texture = picture
	set_icon("" if picture != null else a_fallback_letter)


## Fill the main (rightmost) column to `ratio` (0..1), upward, in `a_color`.
func set_main_bar(a_ratio: float, a_color: Color) -> void:
	_main_bar.visible = true
	_set_vertical_fill(_main_bar, a_ratio, a_color)


## How full the main column is drawn, for a test asking what the card says.
func main_bar_ratio() -> float:
	return _fill_ratio(_main_bar) if _main_bar.visible else 0.0


## How full the garrison bar is drawn, or -1.0 while it is hidden.
func garrison_ratio() -> float:
	if not _garrison_bar.visible:
		return -1.0
	return _fill_ratio(_garrison_bar)


static func _fill_ratio(a_bar: Control) -> float:
	var fill: Node = a_bar.get_node("Fill")
	return float(fill.get_meta(&"ratio")) if fill.has_meta(&"ratio") else 0.0


func dial_count() -> int:
	return _dials.size()


#endregion


#region Private helpers
func _refresh_existing() -> void:
	if not is_instance_valid(_commandable):
		return
	# Direct node lookup rather than the @onready `defense` field, which can read
	# null depending on how the entity entered the tree.
	var defense: Defense = _commandable.get_node_or_null("Defense") as Defense
	if defense != null and defense.hp_max > 0.0:
		set_main_bar(defense.hp / defense.hp_max, HP_COLOR)
	# The garrison bar is there only while someone is inside: an empty host's bar would be a
	# second empty column saying nothing.
	var garrison: Garrison = _commandable.get_node_or_null("Garrison") as Garrison
	var held: int = garrison.occupied_size() if garrison != null else 0
	_garrison_bar.visible = held > 0 and garrison.capacity > 0
	if _garrison_bar.visible:
		_set_vertical_fill(_garrison_bar, float(held) / float(garrison.capacity), GARRISON_COLOR)
	var abilities: Abilities = _commandable.get_node_or_null("Abilities") as Abilities
	for i: int in _dials.size():
		var source: Variant = _dial_sources[i]
		if source is Production and is_instance_valid(source):
			_dials[i].show_state(ChargeDial.production_state(source as Production))
		elif source is int and abilities != null:
			_dials[i].show_state(ChargeDial.pool_state(abilities, source as int))
		elif source is Weapon and is_instance_valid(source):
			_dials[i].show_state(ChargeDial.weapon_state(source as Weapon))


## One dial for a producer's queue, then one per ability pool that has something to cast, then
## one per slow weapon. A card that cannot fit them all reports it and draws the first that
## fit — the importer warns about the same piece before it ever gets here.
func _build_dials(a_commandable: Commandable) -> void:
	for dial: ChargeDial in _dials:
		dial.queue_free()
	_dials.clear()
	var sources: Array = []
	if a_commandable.production != null:
		sources.append(a_commandable.production)
	var abilities: Abilities = a_commandable.get_node_or_null("Abilities") as Abilities
	if abilities != null:
		for i: int in abilities.pool_count():
			if _pool_has_cast(abilities, i):
				sources.append(i)
	sources.append_array(ChargeDial.dial_weapons(a_commandable))
	var capacity: int = dial_capacity(custom_minimum_size.y)
	if sources.size() > capacity:
		push_error(
			(
				"CommandableCard: %s needs %d charge dials, a card fits %d; drawing the first %d"
				% [a_commandable.id, sources.size(), capacity, capacity]
			)
		)
		sources.resize(capacity)
	_dial_sources = sources
	for _source: Variant in sources:
		var dial := ChargeDial.new()
		dial.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_dial_box.add_child(dial)
		_dials.append(dial)
	_layout()


## Whether pool `a_index` grants anything that is CAST. A pool of passives (a Warlord's
## Retinue, a Compound's Work Detail) is never spent, so a dial for it would only ever be full.
static func _pool_has_cast(a_abilities: Abilities, a_index: int) -> bool:
	var grants: Array = a_abilities.groups[a_index].get("grants", [])
	return grants.any(
		func(id: Variant) -> bool:
			var ability: StringName = StringName(id)
			return not AbilityCatalog.has(ability) or not AbilityCatalog.is_passive(ability)
	)


func _refresh_training() -> void:
	if not is_instance_valid(_producer) or _producer.production == null:
		return
	# Guard: the queue may have shrunk (unit finished) before our owner rebuilds.
	if _job_index >= _producer.production.job_count():
		return
	set_main_bar(_producer.production.job_progress(_job_index), TRAINING_COLOR)


## Fill fraction is how much of the price the commander has banked, so a queued purchase
## visibly fills as energy comes in. A funded one (paid for, waiting on its builder) shows a
## full green bar instead.
func _refresh_purchase() -> void:
	if _transaction == null or _transaction.commander == null:
		return
	if _transaction.is_funded():
		set_main_bar(1.0, FUNDED_COLOR)
		return
	var cost: int = maxi(_transaction.energy_cost, _transaction.dominion_cost)
	var banked: int = (
		_transaction.commander.energy
		if _transaction.energy_cost > 0
		else _transaction.commander.dominion
	)
	set_main_bar(1.0 if cost <= 0 else float(banked) / float(cost), PURCHASE_COLOR)


## A vertical bar: a dark track with a fill that grows UP from the bottom (see
## _set_vertical_fill). Placed by _layout, so it carries no geometry of its own.
func _make_vertical_bar(a_name: String) -> Control:
	var bar := Control.new()
	bar.name = a_name
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := ColorRect.new()
	track.color = BAR_BG_COLOR
	track.set_anchors_preset(Control.PRESET_FULL_RECT)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(track)
	var fill := ColorRect.new()
	fill.name = "Fill"
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(fill)
	add_child(bar)
	return bar


## Fill `a_bar` to `a_ratio` from the bottom. Placed in WHOLE PIXELS with the bottom edge pinned
## to the bar's: a fill anchored at a fractional height left a sliver of track showing under it,
## and a bar a pixel off its figure is invisible where one gapped at the bottom is not. Placed
## from the bar's current size every call, so a resize is followed on the next refresh.
static func _set_vertical_fill(a_bar: Control, a_ratio: float, a_color: Color) -> void:
	var fill := a_bar.get_node("Fill") as ColorRect
	var ratio: float = clampf(a_ratio, 0.0, 1.0)
	var height: float = roundf(a_bar.size.y * ratio)
	fill.color = a_color
	fill.set_anchors_preset(Control.PRESET_TOP_LEFT)
	fill.position = Vector2(0.0, a_bar.size.y - height)
	fill.size = Vector2(a_bar.size.x, height)
	# The figure as given, for a readout that wants it rather than the rounded pixels.
	fill.set_meta(&"ratio", ratio)


## Place the picture and the two right-hand columns for the card's current size. Positions
## are set rather than left to containers because the columns are fractions of the HEIGHT
## while the picture takes whatever WIDTH is left, which no single container expresses.
func _layout() -> void:
	if _main_bar == null:
		return
	var height: float = size.y
	var main_width: float = maxf(MIN_COLUMN_WIDTH, roundf(height * MAIN_COLUMN_FRACTION))
	var dial: float = roundf(height * DIAL_FRACTION)
	var dial_row: float = roundf(height * DIAL_ROW_FRACTION)
	var main_x: float = size.x - main_width
	var dial_x: float = main_x - COLUMN_GAP - dial
	_place(_main_bar, Rect2(main_x, 0.0, main_width, height))
	_place(_dial_box, Rect2(dial_x, 0.0, dial, dial_row))
	var garrison_width: float = maxf(MIN_COLUMN_WIDTH, roundf(dial * GARRISON_BAR_FRACTION))
	_place(
		_garrison_bar,
		Rect2(
			dial_x + (dial - garrison_width) / 2.0,
			dial_row + COLUMN_GAP,
			garrison_width,
			maxf(0.0, height - dial_row - COLUMN_GAP)
		)
	)
	for d: ChargeDial in _dials:
		d.custom_minimum_size = Vector2(dial, dial)
	_place(_picture, Rect2(Vector2.ZERO, size))
	var text: Rect2 = label_rect()
	_place(_icon, text)
	for label: Label in [_badge, _glyph]:
		if label != null:
			_place(label, Rect2(text.position, Vector2(text.size.x, label.size.y)))


static func _place(a_node: Control, a_rect: Rect2) -> void:
	a_node.set_anchors_preset(Control.PRESET_TOP_LEFT)
	a_node.position = a_rect.position
	a_node.size = a_rect.size


## Capitalized first letter of a scene's file name, e.g. ".../warlord.tscn" -> "W".
static func _letter(scene_path: String) -> String:
	return _first_letter(scene_path.get_file().get_basename())


## Capitalized first letter of any identifier, or "?" when there isn't one.
static func _first_letter(text: String) -> String:
	return text.substr(0, 1).to_upper() if not text.is_empty() else "?"
#endregion
