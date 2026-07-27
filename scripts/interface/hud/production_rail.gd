class_name ProductionRail
extends Control

## The commander's global production queue, given a permanent home on the left edge.
##
## Replaces the queue readout that lived in InfoView's NOTHING-SELECTED state — the one
## moment a player in a fight never has. Everything here is visible in every selection
## state, because "what have I committed to" is a question you ask while doing something
## else.
##
## Laid out as a single VERTICAL column, top = next to dispatch, matching
## ProductionQueue.entries. Deliberately not the horizontal wrapping strip the genre
## usually puts in this screen position: those hold concurrent, unordered work, whereas this
## queue is strictly ordered with deliberate head-of-line blocking, and a wrapping grid makes
## reading order ambiguous exactly where order is the mechanic.
##
## Four rules keep it small, and they are all "say less when there is less to say":
##   1. only the HEAD carries words — head-of-line blocking means the head's status explains
##      the whole queue, so everything behind it is a bare chip;
##   2. blocker glyphs appear only when a purchase is actually stuck, so a healthy economy
##      draws plain chips;
##   3. runs of identical adjacent purchases collapse to one chip badged ×N;
##   4. the one-off tier is capped, with the remainder gathered into a +N chip.
##
## The two tiers are one list separated by a labelled hairline rather than drawn as two
## panels — that is the honest picture of `entries`, and it makes the standing tier's
## deliberate starvation visible instead of something the player infers from things not
## happening.

#region Constants
const CHIP_SIZE: Vector2 = Vector2(32, 32)
const HEAD_CHIP_SIZE: Vector2 = Vector2(38, 38)
const PANEL_WIDTH: float = 150.0

## How many one-off chips are drawn after the head before the rest collapse into a +N chip.
## The cap is what stops a loaded queue from becoming a column of squares down the screen.
const MAX_VISIBLE_CHIPS: int = 6

const PANEL_COLOR: Color = Color(0.055, 0.067, 0.051, 0.87)
const MUTED_COLOR: Color = Color(0.60, 0.63, 0.59)
const TEXT_COLOR: Color = Color(0.86, 0.87, 0.86)
const DIVIDER_COLOR: Color = Color(0.29, 0.32, 0.28)

## Blocker glyphs. The two blockers have completely different remedies — find energy, versus
## free up or build a producer — so a stuck chip NAMES which one applies rather than just
## looking stuck (see ProductionQueue.Blocker).
const GLYPH_UNAFFORDABLE: String = "◆"
const GLYPH_NO_PRODUCER: String = "▤"
## A FUNDED build has left the queue conceptually — it is paid for and its builder is
## walking — but it still holds the player's energy, so it keeps a chip and says why.
const GLYPH_IN_TRANSIT: String = "→"

const COLOR_UNAFFORDABLE: Color = Color(0.88, 0.68, 0.23)
const COLOR_NO_PRODUCER: Color = Color(0.85, 0.41, 0.23)
const COLOR_IN_TRANSIT: Color = Color(0.30, 0.78, 0.41)

## A left edge stripe distinguishing a BUILD entry from a TRAIN one — the two behave
## differently enough (a build reserves and waits on a builder) to be worth telling apart
## without reading the name.
const BUILD_STRIPE_COLOR: Color = Color(0.44, 0.56, 0.72)
## Applied to chips that cannot land on the current selection — the "producer affinity"
## dimming that recovers what a per-structure queue used to show, as a filter over the
## global queue rather than a second data structure.
const UNRELATED_MODULATE: Color = Color(1.0, 1.0, 1.0, 0.32)

## Chips sit on this panel's dark backing, which the card's own default was not chosen
## against — see CommandableCard.DEFAULT_BACKGROUND_COLOR.
const CHIP_BACKGROUND_COLOR: Color = Color(0.15, 0.17, 0.14, 0.95)

const HEADER_FONT_SIZE: int = 11
const HEAD_NAME_FONT_SIZE: int = 12
#endregion

#region Properties
## The commander whose queue this draws. Injected by RTSController at _ready.
var commander: Commander = null

## The controller, for the one thing the rail cannot answer itself: RIGHT-clicking a queued
## purchase SELECTS the unit it will produce, so the player can order it before it exists.
## Injected by RTSController the same way `commander` is; null simply means those clicks do
## nothing, which is the right behaviour for a rail with no controller behind it.
var controller: RTSController = null

var _header_label: Label
var _clear_queued_button: Button
var _head_panel: Control
var _head_stripe: ColorRect
var _head_card: CommandableCard
var _head_name: Label
var _head_detail: Label
var _head_blocker: Label
var _chips: HFlowContainer
var _standing_divider: Control
var _clear_standing_button: Button
var _standing_chips: HFlowContainer

## Guards the (comparatively expensive) card rebuild. The head's TEXT is refreshed every
## frame regardless — its cost fill and blocker change continuously with income while the
## queue itself sits still.
var _signature: String = ""
## The selection last handed to update(), used for the affinity dimming.
var _selection: Array = []
#endregion

#region Lifecycle
func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	# custom_minimum_size only binds inside a CONTAINER, and this panel's parent is a plain
	# CanvasLayer — so a rail built in code (or authored with no width) would sit at zero
	# width with its full-rect background collapsed to nothing. An authored width still wins.
	if size.x <= 0.0:
		size.x = PANEL_WIDTH
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var background := ColorRect.new()
	background.name = "Background"
	background.color = PANEL_COLOR
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.set_anchors_preset(Control.PRESET_FULL_RECT)
	rows.offset_left = 7.0
	rows.offset_top = 6.0
	rows.offset_right = -7.0
	rows.offset_bottom = -6.0
	rows.add_theme_constant_override("separation", 4)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rows)

	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header_label = _make_label(HEADER_FONT_SIZE, MUTED_COLOR)
	_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_header_label)
	_clear_queued_button = _make_clear_button(
		"Cancel every one-off purchase",
		(
			"Cancel every one-off purchase waiting in the queue; anything already reserved is"
			+ " refunded in full.\nStanding orders are left alone, so they start re-filling the"
			+ " queue behind this."
		)
	)
	_clear_queued_button.pressed.connect(_on_clear_queued_pressed)
	header.add_child(_clear_queued_button)
	rows.add_child(header)

	_build_head_panel(rows)

	_chips = HFlowContainer.new()
	_chips.name = "Chips"
	_chips.add_theme_constant_override("h_separation", 4)
	_chips.add_theme_constant_override("v_separation", 4)
	_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(_chips)

	_build_standing_divider(rows)

	_standing_chips = HFlowContainer.new()
	_standing_chips.name = "StandingChips"
	_standing_chips.add_theme_constant_override("h_separation", 4)
	_standing_chips.add_theme_constant_override("v_separation", 4)
	_standing_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(_standing_chips)

func _process(_a_delta: float) -> void:
	_refresh()
#endregion

#region Public API
## Called every frame by the controller with the current selection. The selection is only
## used for affinity dimming — the rail itself is never gated by it.
func update(a_selection: Array) -> void:
	_selection = a_selection
	_refresh()

## The queued purchase the cursor is currently over, or null.
##
## The other direction of producer affinity: the controller feeds this to
## ProducerAffinityIndicator, which rings the structures that could build it. Dimming answers
## "what will this building make?"; this answers "where will this purchase go?".
##
## A linear scan over the few visible chips, run unconditionally each frame — the same shape
## and the same cost as InfoView.hovered_training_target.
func hovered_transaction() -> PurchaseTransaction:
	if not visible:
		return null
	for container: Node in [_head_card, _chips, _standing_chips]:
		if container == null:
			continue
		var cards: Array = [container] if container is CommandableCard else container.get_children()
		for node: Node in cards:
			var card := node as CommandableCard
			if card != null and card.is_hovered_purchase():
				return card.hovered_transaction()
	return null
#endregion

## Hand `a_card`'s right-click to the controller, and paint its green border if the run it
## stands for is already selected.
##
## Called on every rebuild, because the rail frees and rebuilds its chips whenever the queue
## changes — a connection made to a freed card is not a connection. The HEAD card is the
## exception: it is built once in _ready and only rebound, so the connect is guarded rather
## than repeated (Godot errors on a duplicate connection).
##
## Hand `a_card`'s right-click to the controller. The BORDER is not painted here — it follows
## the selection rather than the card set, so it is repainted every frame by
## _refresh_pending_borders instead.
##
## Called on every rebuild, because the rail frees and rebuilds its chips whenever the queue
## changes — a connection made to a freed card is not a connection. The HEAD card is the
## exception: it is built once in _ready and only rebound, so the connect is guarded rather
## than repeated (Godot errors on a duplicate connection).
func _wire_pending_selection(a_card: CommandableCard, a_run: Array) -> void:
	if controller == null or a_run.is_empty():
		return
	if not a_card.pending_selected.is_connected(_on_pending_selected):
		a_card.pending_selected.connect(_on_pending_selected)


## A right click on a purchase card. `a_all_of_type` is the broaden modifier: take every
## PENDING purchase of the same piece across the whole queue, not just the run that was
## clicked — the same "all of them" that modifier means on a selector.
func _on_pending_selected(a_transactions: Array, a_additive: bool, a_all_of_type: bool) -> void:
	if controller == null:
		return
	var wanted: Array = a_transactions
	if a_all_of_type and not a_transactions.is_empty():
		wanted = _pending_of_type((a_transactions.front() as PurchaseTransaction).type)
	controller.select_pending(wanted, a_additive)


## Repaint every chip's selected border from the live pending selection. Cheap: a handful of
## visible chips, and the same per-frame scan `hovered_transaction` already does.
func _refresh_pending_borders() -> void:
	if controller == null:
		return
	for node: Node in _all_purchase_cards():
		var card := node as CommandableCard
		card.set_pending_selected(_card_is_selected(card))


## Whether anything the card stands for is selected. Asked of ANY member of a collapsed run
## rather than only its head — the card stands for the run, and one that stood for a selected
## purchase while showing no border would misreport what the next order reaches.
func _card_is_selected(a_card: CommandableCard) -> bool:
	for entry: Variant in a_card.purchase_group():
		if controller.is_pending_selected(entry as PurchaseTransaction):
			return true
	return false


## Every chip currently drawn that stands for a purchase, head panel included.
func _all_purchase_cards() -> Array:
	var out: Array = []
	for container: Node in [_head_card, _chips, _standing_chips]:
		if container == null:
			continue
		var cards: Array = [container] if container is CommandableCard else container.get_children()
		for node: Node in cards:
			var card := node as CommandableCard
			if card != null and card.hovered_transaction() != null:
				out.append(card)
	return out


## Every still-orderable purchase in the queue buying `a_type`.
func _pending_of_type(a_type: StringName) -> Array:
	var queue: ProductionQueue = _queue()
	if queue == null:
		return []
	var out: Array = []
	for entry: PurchaseTransaction in queue.entries:
		if entry.type == a_type and entry.awaits_its_unit():
			out.append(entry)
	return out


#region Refresh
func _queue() -> ProductionQueue:
	return commander.production_queue if commander != null else null

func _refresh() -> void:
	var queue: ProductionQueue = _queue()
	if queue == null:
		visible = false
		return

	# The whole panel goes away with an empty queue. A permanently-present empty container is
	# noise, and its absence is itself informative — nothing is on order.
	visible = not queue.is_empty()
	if not visible:
		return

	var signature: String = _build_signature(queue)
	if signature != _signature:
		_signature = signature
		_rebuild(queue)
	# Cost fills and the blocker track income, which changes with nothing to signal it.
	_refresh_head_text(queue)
	# So does the PENDING SELECTION: right-clicking a chip changes which phantom is selected
	# without changing which chips exist, so the signature above does not move and the rebuild
	# that paints the borders never runs. Painted every frame instead — the same reason
	# InfoView._refresh_pending_borders is not on its own card-rebuild gate.
	_refresh_pending_borders()

	# Height follows content: the chip rows grow and shrink with the queue, and the standing
	# divider disappears entirely with an empty ring, so a fixed rect would leave the panel
	# background running on past the last chip.
	var rows: Control = get_node_or_null("Rows") as Control
	if rows != null:
		custom_minimum_size.y = rows.get_combined_minimum_size().y + 12.0
		size.y = custom_minimum_size.y

## Covers everything that changes which CARDS exist: the entries themselves, their tier and
## state, and the selection (which decides the affinity dimming).
func _build_signature(a_queue: ProductionQueue) -> String:
	var signature: String = ""
	for transaction: PurchaseTransaction in a_queue.entries:
		signature += "%d:%d:%d|" % [transaction.id, transaction.state, transaction.sequence]
	for node: Node in _selection:
		signature += "s%d|" % node.get_instance_id()
	return signature

func _rebuild(a_queue: ProductionQueue) -> void:
	var one_offs: Array[PurchaseTransaction] = a_queue.queued()
	var head: PurchaseTransaction = one_offs.front() if not one_offs.is_empty() else null

	_header_label.text = "production  ·  %d" % one_offs.size() if not one_offs.is_empty() \
		else "production"
	_clear_queued_button.visible = not one_offs.is_empty()

	_rebuild_head(a_queue, head)
	_rebuild_one_off_chips(a_queue, one_offs)
	_rebuild_standing(a_queue)

## The head is the one entry that carries words. It is the front of the NON-STANDING tier,
## not of `entries` overall: with no one-offs queued there is nothing being held up, and the
## ring's own next-up mark already says which template runs next — promoting a standing entry
## into the head panel would draw it twice and imply it was blocking something.
func _rebuild_head(a_queue: ProductionQueue, a_head: PurchaseTransaction) -> void:
	_head_panel.visible = a_head != null
	if a_head == null:
		return
	_head_card.set_card_size(HEAD_CHIP_SIZE)
	_head_card.set_background_color(CHIP_BACKGROUND_COLOR)
	_head_card.bind_purchase(a_head, a_queue)
	_wire_pending_selection(_head_card, [a_head])
	_head_name.text = String(a_head.type)
	_head_stripe.color = BUILD_STRIPE_COLOR if a_head.kind == PurchaseTransaction.Kind.BUILD \
		else _blocker_color(a_queue.blocker_for(a_head))

func _rebuild_one_off_chips(a_queue: ProductionQueue, a_one_offs: Array) -> void:
	_clear(_chips)
	# Everything after the head, since the head has its own panel above.
	var tail: Array = a_one_offs.slice(1) if a_one_offs.size() > 1 else []
	var runs: Array = _collapse_runs(tail)

	var drawn: int = 0
	var hidden: int = 0
	for run: Array in runs:
		if drawn >= MAX_VISIBLE_CHIPS:
			hidden += run.size()
			continue
		var card := CommandableCard.new()
		_chips.add_child(card)
		card.set_card_size(CHIP_SIZE)
		card.set_background_color(CHIP_BACKGROUND_COLOR)
		card.bind_purchase_group(run, a_queue)
		_wire_pending_selection(card, run)
		_apply_chip_state(card, run.front() as PurchaseTransaction, a_queue)
		drawn += 1
	if hidden > 0:
		_chips.add_child(_make_overflow_chip(hidden))

## The standing ring, in AUTHORED order rather than dispatch order (see
## ProductionQueue.standing_ring): the ring holds still and a cursor moves through it, which
## is what a cycle of "three recruits then a tank" has to look like. Drawing `entries` order
## instead would show the ring shuffling every time a template rotated.
func _rebuild_standing(a_queue: ProductionQueue) -> void:
	_clear(_standing_chips)
	var ring: Array[PurchaseTransaction] = a_queue.standing_ring()
	_standing_divider.visible = not ring.is_empty()
	_standing_chips.visible = not ring.is_empty()
	if ring.is_empty():
		return

	var next: PurchaseTransaction = a_queue.standing_next()
	for run: Array in _collapse_runs(ring):
		var card := CommandableCard.new()
		_standing_chips.add_child(card)
		card.set_card_size(CHIP_SIZE)
		card.set_background_color(CHIP_BACKGROUND_COLOR)
		card.bind_purchase_group(run, a_queue)
		# The ring is drawn dimmer than the one-off tier because it only ever runs when nothing
		# else wants a producer; the next-up template is drawn at full strength so the cursor is
		# legible against it.
		var is_next: bool = run.has(next)
		card.modulate = Color(1, 1, 1) if is_next else Color(1, 1, 1, 0.55)
		if is_next and run.size() == 1:
			card.set_badge("▸", TEXT_COLOR)
		_apply_affinity(card, run.front() as PurchaseTransaction)

## Per-chip state that is not the fill bar: the blocker glyph (only when actually blocked)
## and the affinity dimming.
func _apply_chip_state(
	a_card: CommandableCard,
	a_transaction: PurchaseTransaction,
	a_queue: ProductionQueue
) -> void:
	if a_transaction.kind == PurchaseTransaction.Kind.BUILD and a_transaction.is_funded():
		a_card.set_glyph(GLYPH_IN_TRANSIT, COLOR_IN_TRANSIT)
	else:
		match a_queue.blocker_for(a_transaction):
			ProductionQueue.Blocker.UNAFFORDABLE:
				a_card.set_glyph(GLYPH_UNAFFORDABLE, COLOR_UNAFFORDABLE)
			ProductionQueue.Blocker.NO_FREE_PRODUCER:
				a_card.set_glyph(GLYPH_NO_PRODUCER, COLOR_NO_PRODUCER)
	_apply_affinity(a_card, a_transaction)

## Dim a chip that cannot land on anything currently selected.
##
## This is the direction of producer affinity that RECOVERS the per-structure queue: select a
## Stronghold and the rail shows what that Stronghold's queue used to show, as a filter over
## the global queue rather than as a second data structure. With nothing selected — or with a
## selection holding no eligible producer — nothing is dimmed, since there is no filter being
## expressed.
func _apply_affinity(a_card: CommandableCard, a_transaction: PurchaseTransaction) -> void:
	if _selection.is_empty() or a_transaction.kind != PurchaseTransaction.Kind.TRAIN:
		return
	var candidates: Array = a_transaction.candidate_producers()
	if candidates.is_empty():
		return
	var selection_has_producer: bool = false
	var selection_can_take: bool = false
	for node: Node in _selection:
		var commandable: Commandable = node as Commandable
		if commandable == null or commandable.production == null:
			continue
		selection_has_producer = true
		if candidates.has(commandable):
			selection_can_take = true
			break
	if selection_has_producer and not selection_can_take:
		a_card.modulate = UNRELATED_MODULATE

## The head's live text: how much of the price is banked, and what it is waiting on.
func _refresh_head_text(a_queue: ProductionQueue) -> void:
	if not _head_panel.visible or commander == null:
		return
	var head: PurchaseTransaction = a_queue.queued().front() if not a_queue.queued().is_empty() \
		else null
	if head == null:
		return

	# A funded entry is PAID — purchases are charged at request time — so the cost readout has
	# nothing left to count down. What it is waiting for depends on its kind: a build wants its
	# builder to walk over, a unit wants a producer to come free.
	if head.is_funded():
		var blocker: ProductionQueue.Blocker = a_queue.blocker_for(head)
		if blocker == ProductionQueue.Blocker.NO_FREE_PRODUCER:
			_head_detail.text = "paid  ·  no free producer"
			_head_blocker.visible = false
			return
		_head_detail.text = "paid  ·  waiting on its builder" \
			if head.kind == PurchaseTransaction.Kind.BUILD else "paid  ·  starting"
		_head_blocker.visible = false
		return

	var cost: int = maxi(head.energy_cost, head.dominion_cost)
	var banked: int = commander.energy if head.energy_cost > 0 else commander.dominion
	_head_detail.text = "%d / %d" % [mini(banked, cost), cost]

	var blocker: ProductionQueue.Blocker = a_queue.blocker_for(head)
	_head_blocker.visible = blocker != ProductionQueue.Blocker.NONE
	match blocker:
		ProductionQueue.Blocker.UNAFFORDABLE:
			_head_blocker.text = "waiting on energy"
			_head_blocker.add_theme_color_override("font_color", COLOR_UNAFFORDABLE)
		ProductionQueue.Blocker.NO_FREE_PRODUCER:
			_head_blocker.text = "no free producer"
			_head_blocker.add_theme_color_override("font_color", COLOR_NO_PRODUCER)
#endregion

#region Construction helpers
func _build_head_panel(a_parent: Node) -> void:
	_head_panel = Control.new()
	_head_panel.name = "Head"
	_head_panel.custom_minimum_size = Vector2(0.0, HEAD_CHIP_SIZE.y + 12.0)
	_head_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# A single-sided accent, so it reads as a marker on the row rather than as a border.
	_head_stripe = ColorRect.new()
	_head_stripe.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_head_stripe.offset_right = 2.0
	_head_stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_head_panel.add_child(_head_stripe)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 6.0
	row.offset_top = 5.0
	row.offset_bottom = -5.0
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_head_panel.add_child(row)

	_head_card = CommandableCard.new()
	row.add_child(_head_card)

	var text_column := VBoxContainer.new()
	text_column.add_theme_constant_override("separation", 0)
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_head_name = _make_label(HEAD_NAME_FONT_SIZE, TEXT_COLOR)
	_head_detail = _make_label(HEADER_FONT_SIZE, MUTED_COLOR)
	_head_blocker = _make_label(HEADER_FONT_SIZE, COLOR_UNAFFORDABLE)
	text_column.add_child(_head_name)
	text_column.add_child(_head_detail)
	text_column.add_child(_head_blocker)
	row.add_child(text_column)

	a_parent.add_child(_head_panel)

func _build_standing_divider(a_parent: Node) -> void:
	_standing_divider = HBoxContainer.new()
	_standing_divider.name = "StandingDivider"
	(_standing_divider as HBoxContainer).add_theme_constant_override("separation", 5)
	_standing_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var line := ColorRect.new()
	line.color = DIVIDER_COLOR
	line.custom_minimum_size = Vector2(0.0, 1.0)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_standing_divider.add_child(line)

	var caption := _make_label(HEADER_FONT_SIZE, MUTED_COLOR)
	caption.text = "standing"
	_standing_divider.add_child(caption)

	_clear_standing_button = _make_clear_button(
		"Cancel the standing ring",
		(
			"Cancel every standing order, refunding anything already reserved.\nThe one-off queue"
			+ " is left alone. Nothing re-fills the queue afterwards, so idle income stops being"
			+ " spent until you order something."
		)
	)
	_clear_standing_button.pressed.connect(_on_clear_standing_pressed)
	_standing_divider.add_child(_clear_standing_button)

	a_parent.add_child(_standing_divider)

## The chip standing in for everything past the cap. Not a CommandableCard: it represents no
## single purchase, so it has no icon, no bar and nothing to cancel.
func _make_overflow_chip(a_count: int) -> Control:
	var chip := Control.new()
	chip.custom_minimum_size = CHIP_SIZE
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := ColorRect.new()
	background.color = Color(0.1, 0.1, 0.1, 0.5)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(background)
	var label := _make_label(HEADER_FONT_SIZE, MUTED_COLOR)
	label.text = "+%d" % a_count
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.add_child(label)
	return chip

func _make_label(a_font_size: int, a_color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", a_font_size)
	label.add_theme_color_override("font_color", a_color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _make_clear_button(a_simple: String, a_verbose: String) -> Button:
	var button := VerboseTooltipButton.new()
	button.name = "Clear"
	button.text = "×"
	button.focus_mode = Control.FOCUS_NONE
	# CURSOR_POINTING_HAND carries the game's own pointer art, registered once in
	# RTSController._register_hud_cursor. Asking for a shape with no art behind it is what
	# drops the cursor to the OS default — see hud-layout.md.
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", HEADER_FONT_SIZE)
	button.simple_tooltip = a_simple
	button.verbose_tooltip = a_verbose
	return button
#endregion

#region Private helpers
## Group ADJACENT entries of the same piece into runs. Adjacency is the whole constraint:
## the queue's order is meaningful, so folding two separated runs of Recruits together would
## claim a dispatch order the queue does not have.
static func _collapse_runs(transactions: Array) -> Array:
	var runs: Array = []
	var current: Array = []
	for transaction: PurchaseTransaction in transactions:
		if not current.is_empty() \
				and (current.front() as PurchaseTransaction).type != transaction.type:
			runs.append(current)
			current = []
		current.append(transaction)
	if not current.is_empty():
		runs.append(current)
	return runs

func _blocker_color(a_blocker: ProductionQueue.Blocker) -> Color:
	match a_blocker:
		ProductionQueue.Blocker.UNAFFORDABLE:
			return COLOR_UNAFFORDABLE
		ProductionQueue.Blocker.NO_FREE_PRODUCER:
			return COLOR_NO_PRODUCER
	return DIVIDER_COLOR

func _on_clear_queued_pressed() -> void:
	if _queue() != null:
		_queue().clear_queued()

func _on_clear_standing_pressed() -> void:
	if _queue() != null:
		_queue().clear_standing()

## Detaches children immediately (so they aren't laid out for a stale frame) and frees them.
func _clear(a_container: Node) -> void:
	for child: Node in a_container.get_children():
		a_container.remove_child(child)
		child.queue_free()
#endregion
