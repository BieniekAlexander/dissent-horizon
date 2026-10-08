class_name ProductionRail
extends Control

## A readout of production: what is being made right now, what is queued behind it, and the
## standing orders that refill the queue when it runs dry. One component, drawn in two places
## (gdd/systems/ux/ui/hud-layout.md §Production):
##
##   * GLOBAL — the commander's whole queue, in the bottom-centre slot the selection's info
##     panel otherwise holds. Shown only while NOTHING is selected: the two are mutually
##     exclusive, so the screen's centre is either "what you are holding" or "what you have
##     committed to".
##   * SCOPED (`is_scoped`) — inside the info panel's Details pane, while the command card is
##     on its PRODUCTION page: only what the producers of the current producer context are
##     making, and only the purchases that could land on them.
##
## Three columns, left to right: PRODUCING (one card per busy producer), QUEUED (the one-off
## tier, its head with words), STANDING (the ring). Columns rather than rows because the slot
## is wide and short; inside a column, chips run left to right in dispatch order, and the
## tier boundary is the column boundary, so reading order is never ambiguous.
##
## Four rules keep it small, and they are all "say less when there is less to say":
##   1. only the HEAD carries words — head-of-line blocking means the head's status explains
##      the whole queue, so everything behind it is a bare chip;
##   2. blocker glyphs appear only when a purchase is actually stuck, so a healthy economy
##      draws plain chips;
##   3. runs of identical adjacent purchases collapse to one chip badged ×N;
##   4. the one-off tier is capped, with the remainder gathered into a +N chip.
## In the global view an empty column is dropped, and the whole panel with it when there is
## nothing at all. The scoped view keeps every column, saying "none", because it answers a
## question the player asked by opening the page.
##
## The global view is COMPACT: one strip of cards, sized to what it holds and pinned to the
## bottom centre of its parent, because with nothing selected the player is looking at the
## world, and every pixel this takes is battlefield they cannot see. The scoped view fills the
## Details pane it is given and wraps.

#region Constants
const CHIP_SIZE: Vector2 = Vector2(32, 32)
const HEAD_CHIP_SIZE: Vector2 = Vector2(38, 38)

## How many one-off chips are drawn after the head before the rest collapse into a +N chip.
## The cap is what stops a loaded queue from filling the slot with squares.
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
## The standing ring only runs when nothing else wants a producer, so it is drawn dimmer than
## the one-off tier; the next-up template is drawn at full strength so the cursor shows.
const STANDING_MODULATE: Color = Color(1.0, 1.0, 1.0, 0.55)

## Chips sit on a dark backing, which the card's own default was not chosen against — see
## CommandableCard.DEFAULT_BACKGROUND_COLOR.
const CHIP_BACKGROUND_COLOR: Color = Color(0.15, 0.17, 0.14, 0.95)

const HEADER_FONT_SIZE: int = 11
const HEAD_NAME_FONT_SIZE: int = 12
const PADDING: float = 6.0
const COLUMN_SEPARATION: int = 8
## The queue column gets the most room: it is the only one with words in it.
const QUEUE_COLUMN_STRETCH: float = 2.0
#endregion

#region Properties
## True for the copy inside the info panel: filtered to `scope`, no backing of its own (the
## panel has one), and every column kept even when empty. Authored per instance.
@export var is_scoped: bool = false

## The commander whose queue this draws. Injected by RTSController (the global copy) or by
## InfoView (the scoped one).
var commander: Commander = null

## The controller, for the one thing the panel cannot answer itself: RIGHT-clicking a queued
## purchase or a job SELECTS the unit it will produce, so the player can order it before it
## exists. Injected the same way `commander` is; null simply means those clicks do nothing.
var controller: RTSController = null

## Whether the panel may show at all. The controller turns the global copy off while
## something is selected; InfoView turns the scoped copy off outside the PRODUCTION page.
var is_active: bool = true

## The producers a scoped panel is about. Ignored when not `is_scoped`.
var _scope: Array = []

var _background: ColorRect
var _producing_column: Control
var _producing_caption: Label
var _producing_cards: Container
var _producing_none: Label
var _queued_column: Control
var _queued_caption: Label
var _clear_queued_button: Button
var _head_panel: Control
var _head_stripe: ColorRect
var _head_card: CommandableCard
var _head_name: Label
var _head_detail: Label
var _head_blocker: Label
var _chips: Container
var _queued_none: Label
var _standing_column: Control
var _clear_standing_button: Button
var _standing_chips: Container
var _standing_none: Label
var _dividers: Array[Control] = []
var _columns: HBoxContainer

## Guards the (comparatively expensive) card rebuild. The head's TEXT is refreshed every
## frame regardless — its cost fill and blocker change continuously with income while the
## queue itself sits still.
var _signature: String = ""
## What the last rebuild drew, kept so the clear buttons cancel exactly that and the head's
## text can be refreshed without re-filtering the queue.
var _one_offs: Array[PurchaseTransaction] = []
var _ring: Array[PurchaseTransaction] = []
var _head: PurchaseTransaction = null
#endregion


#region Lifecycle
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_background = ColorRect.new()
	_background.name = "Background"
	_background.color = PANEL_COLOR
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.visible = not is_scoped
	add_child(_background)

	var columns := HBoxContainer.new()
	columns.name = "Columns"
	columns.set_anchors_preset(Control.PRESET_FULL_RECT)
	columns.offset_left = PADDING
	columns.offset_top = PADDING
	columns.offset_right = -PADDING
	columns.offset_bottom = -PADDING
	columns.add_theme_constant_override("separation", COLUMN_SEPARATION)
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(columns)
	_columns = columns
	# A global strip wider than its slot is cut off rather than spilling over the minimap.
	clip_contents = not is_scoped

	_build_producing_column(columns)
	_dividers.append(_make_divider(columns))
	_build_queued_column(columns)
	_dividers.append(_make_divider(columns))
	_build_standing_column(columns)


func _process(_a_delta: float) -> void:
	_refresh()


#endregion


#region Public API
## Narrow a scoped panel to `a_producers`. Cheap to call every frame: a changed scope shows up
## in the rebuild signature, an unchanged one costs nothing.
func set_scope(a_producers: Array) -> void:
	_scope = a_producers


## The queued purchase the cursor is currently over, or null.
##
## The other direction of producer affinity: the controller feeds this to
## ProducerAffinityIndicator, which rings the structures that could build it. A linear scan
## over the few visible chips, run unconditionally each frame.
func hovered_transaction() -> PurchaseTransaction:
	if not visible:
		return null
	for card: CommandableCard in _purchase_cards():
		if card.is_hovered_purchase():
			return card.hovered_transaction()
	return null


## The job whose card the mouse is over, as [producer, job_index] — empty when none is.
## Read by RTSController's rally indicator, which then draws that unit's own pre-issued
## orders instead of its producer's head-of-queue rally.
func hovered_training_target() -> Array:
	if not visible:
		return []
	for node: Node in _producing_cards.get_children():
		var card := node as CommandableCard
		if card != null and card.is_hovered_training():
			return [card.training_producer(), card.training_job_index()]
	return []


## Whether `a_transaction` belongs in a panel scoped to `a_scope`: a unit purchase that could
## land on at least one of those producers. A build has no producer, so it is never in scope.
static func is_in_scope(a_transaction: PurchaseTransaction, a_scope: Array) -> bool:
	if a_transaction.kind != PurchaseTransaction.Kind.TRAIN:
		return false
	return a_transaction.candidate_producers().any(
		func(producer: Actor) -> bool: return a_scope.has(producer)
	)


#endregion


#region Pending selection
## Hand `a_card`'s right-click to the controller. The BORDER is not painted here — it follows
## the selection rather than the card set, so it is repainted every frame by
## _refresh_pending_borders instead.
##
## Called on every rebuild, because chips are freed and rebuilt whenever the queue changes — a
## connection made to a freed card is not a connection. The HEAD card is built once in _ready
## and only rebound, so the connect is guarded rather than repeated (Godot errors on a
## duplicate connection).
func _wire_pending_selection(a_card: CommandableCard) -> void:
	if controller == null:
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


## A right click on a job card: select the unit it is building. It has left the production
## queue, so this card is the only place it can be reached.
func _on_job_pending_selected(
	a_transactions: Array, a_additive: bool, _a_all_of_type: bool
) -> void:
	if controller != null:
		controller.select_pending(a_transactions, a_additive)


## Repaint every card's selected border from the live pending selection. Cheap: a handful of
## visible cards, and the same per-frame scan `hovered_transaction` already does.
func _refresh_pending_borders() -> void:
	if controller == null:
		return
	for card: CommandableCard in _purchase_cards():
		card.set_pending_selected(_card_is_selected(card))
	for node: Node in _producing_cards.get_children():
		var job_card := node as CommandableCard
		if job_card == null or not is_instance_valid(job_card.training_producer()):
			continue
		var production: Production = job_card.training_producer().production
		var transaction: PurchaseTransaction = (
			production.job_transaction(job_card.training_job_index())
			if production != null
			else null
		)
		job_card.set_pending_selected(controller.is_pending_selected(transaction))


## Whether anything the card stands for is selected. Asked of ANY member of a collapsed run
## rather than only its head — the card stands for the run, and one that stood for a selected
## purchase while showing no border would misreport what the next order reaches.
func _card_is_selected(a_card: CommandableCard) -> bool:
	for entry: Variant in a_card.purchase_group():
		if controller.is_pending_selected(entry as PurchaseTransaction):
			return true
	return false


## Every card currently drawn that stands for a queued purchase, head included.
func _purchase_cards() -> Array[CommandableCard]:
	var out: Array[CommandableCard] = []
	var candidates: Array = [_head_card]
	candidates.append_array(_chips.get_children())
	candidates.append_array(_standing_chips.get_children())
	for node: Variant in candidates:
		var card := node as CommandableCard
		if card != null and card.is_visible_in_tree() and card.hovered_transaction() != null:
			out.append(card)
	return out


## Every still-orderable purchase in the queue buying `a_type`.
func _pending_of_type(a_type: StringName) -> Array:
	var queue: ProductionQueue = _queue()
	if queue == null:
		return []
	return queue.entries.filter(
		func(entry: PurchaseTransaction) -> bool:
			return entry.type == a_type and entry.awaits_its_unit()
	)


#endregion


#region Refresh
func _queue() -> ProductionQueue:
	return commander.production_queue if commander != null else null


func _refresh() -> void:
	var queue: ProductionQueue = _queue()
	if queue == null or not is_active:
		visible = false
		return

	var busy: Array = _busy_producers()
	var signature: String = _build_signature(queue, busy)
	if signature != _signature:
		_signature = signature
		_rebuild(queue, busy)
	# The scoped view keeps its columns even when empty; the global one has nothing to say
	# about an empty economy, and its absence is itself informative.
	visible = is_scoped or not (busy.is_empty() and _one_offs.is_empty() and _ring.is_empty())
	if not visible:
		return
	# Cost fills and the blocker track income, which changes with nothing to signal it.
	_refresh_head_text(queue)
	if not is_scoped:
		_fit_to_content()
	# So does the PENDING SELECTION: right-clicking a chip changes which phantom is selected
	# without changing which chips exist, so the signature does not move.
	_refresh_pending_borders()


## Size the compact strip to its cards and pin it to the bottom centre of its parent. Every
## frame, because the head's text changes width with income; the anchors (bottom centre, set
## in the scene) keep it placed when the window resizes.
func _fit_to_content() -> void:
	var content: Vector2 = _columns.get_combined_minimum_size() + Vector2.ONE * 2.0 * PADDING
	var parent: Control = get_parent_control()
	var width: float = minf(content.x, parent.size.x) if parent != null else content.x
	offset_left = -width / 2.0
	offset_right = width / 2.0
	offset_top = -content.y
	offset_bottom = 0.0


## The producers whose jobs the PRODUCING column draws: the scope, or everything the
## commander owns.
func _busy_producers() -> Array:
	var producers: Array = _scope if is_scoped else commander.owned_producers()
	return producers.filter(
		func(producer: Variant) -> bool:
			return (
				is_instance_valid(producer)
				and (producer as Actor).production != null
				and (producer as Actor).production.job_count() > 0
			)
	)


## Covers everything that changes which CARDS exist: the entries themselves, their tier and
## state, the jobs running, and the scope.
func _build_signature(a_queue: ProductionQueue, a_busy: Array) -> String:
	var signature: String = ""
	for transaction: PurchaseTransaction in a_queue.entries:
		signature += "%d:%d:%d|" % [transaction.id, transaction.state, transaction.sequence]
	for producer: Actor in a_busy:
		signature += "j%d:%s|" % [producer.get_instance_id(), producer.production.job_type(0)]
	if is_scoped:
		for producer: Variant in _scope:
			signature += "s%d|" % (producer as Object).get_instance_id()
	return signature


func _rebuild(a_queue: ProductionQueue, a_busy: Array) -> void:
	_one_offs = a_queue.queued()
	_ring = a_queue.standing_ring()
	if is_scoped:
		var in_scope: Callable = func(t: PurchaseTransaction) -> bool: return is_in_scope(t, _scope)
		_one_offs.assign(_one_offs.filter(in_scope))
		_ring.assign(_ring.filter(in_scope))
	_head = _one_offs.front() if not _one_offs.is_empty() else null

	_rebuild_producing(a_busy)
	_rebuild_head(a_queue)
	_rebuild_one_off_chips(a_queue)
	_rebuild_standing(a_queue)

	_producing_column.visible = is_scoped or not a_busy.is_empty()
	_queued_column.visible = is_scoped or not _one_offs.is_empty()
	_standing_column.visible = is_scoped or not _ring.is_empty()
	# A divider sits AFTER each of the first two columns; it is drawn only between two columns
	# that are both showing.
	var shown: Array = [_producing_column, _queued_column, _standing_column].filter(
		func(column: Control) -> bool: return column.visible
	)
	_dividers[0].visible = _producing_column.visible and shown.size() > 1
	_dividers[1].visible = _standing_column.visible and shown.size() > 1


## One card per busy producer — a producer builds one thing at a time, so its job IS what it
## is producing. A left click cancels the job (the card does that itself).
func _rebuild_producing(a_busy: Array) -> void:
	_clear(_producing_cards)
	for producer: Actor in a_busy:
		var card := CommandableCard.new()
		_producing_cards.add_child(card)
		card.set_card_size(HEAD_CHIP_SIZE)
		card.set_background_color(CHIP_BACKGROUND_COLOR)
		card.bind_training(producer, 0)
		card.pending_selected.connect(_on_job_pending_selected)
	_producing_none.visible = a_busy.is_empty()
	# How many of the producers being looked at are working, which is the question a selection
	# of several barracks is asking.
	_producing_caption.text = (
		"producing  ·  %d / %d" % [a_busy.size(), _scope.size()]
		if is_scoped and _scope.size() > 1
		else "producing"
	)


## The head is the one entry that carries words. It is the front of the NON-STANDING tier,
## not of `entries` overall: with no one-offs queued there is nothing being held up, and the
## ring's own next-up mark already says which template runs next.
func _rebuild_head(a_queue: ProductionQueue) -> void:
	_queued_caption.text = "queued  ·  %d" % _one_offs.size() if not _one_offs.is_empty() else "queued"
	_clear_queued_button.visible = not _one_offs.is_empty()
	_queued_none.visible = _head == null
	_head_panel.visible = _head != null
	if _head == null:
		return
	_head_card.set_card_size(HEAD_CHIP_SIZE)
	_head_card.set_background_color(CHIP_BACKGROUND_COLOR)
	_head_card.bind_purchase(_head, a_queue)
	_wire_pending_selection(_head_card)
	_head_name.text = String(_head.type)
	_head_stripe.color = (
		BUILD_STRIPE_COLOR
		if _head.kind == PurchaseTransaction.Kind.BUILD
		else _blocker_color(a_queue.blocker_for(_head))
	)


func _rebuild_one_off_chips(a_queue: ProductionQueue) -> void:
	_clear(_chips)
	# Everything after the head, since the head has its own panel above.
	var tail: Array = _one_offs.slice(1) if _one_offs.size() > 1 else []
	var runs: Array = _collapse_runs(tail)

	var drawn: int = 0
	var hidden: int = 0
	for run: Array in runs:
		if drawn >= MAX_VISIBLE_CHIPS:
			hidden += run.size()
			continue
		var card := _make_purchase_chip(_chips, run, a_queue)
		_apply_chip_state(card, run.front() as PurchaseTransaction, a_queue)
		drawn += 1
	if hidden > 0:
		_chips.add_child(_make_overflow_chip(hidden))
	_chips.visible = _chips.get_child_count() > 0


## The standing ring, in AUTHORED order rather than dispatch order (see
## ProductionQueue.standing_ring): the ring holds still and a cursor moves through it, which
## is what a cycle of "three recruits then a tank" has to look like. Drawing `entries` order
## instead would show the ring shuffling every time a template rotated.
func _rebuild_standing(a_queue: ProductionQueue) -> void:
	_clear(_standing_chips)
	_clear_standing_button.visible = not _ring.is_empty()
	_standing_none.visible = _ring.is_empty()
	var next: PurchaseTransaction = a_queue.standing_next()
	for run: Array in _collapse_runs(_ring):
		var card := _make_purchase_chip(_standing_chips, run, a_queue)
		var is_next: bool = run.has(next)
		card.modulate = Color.WHITE if is_next else STANDING_MODULATE
		if is_next and run.size() == 1:
			card.set_badge("▸", TEXT_COLOR)


func _make_purchase_chip(
	a_parent: Node, a_run: Array, a_queue: ProductionQueue
) -> CommandableCard:
	var card := CommandableCard.new()
	a_parent.add_child(card)
	card.set_card_size(CHIP_SIZE)
	card.set_background_color(CHIP_BACKGROUND_COLOR)
	card.bind_purchase_group(a_run, a_queue)
	_wire_pending_selection(card)
	return card


## The blocker glyph, drawn only when the purchase is actually stuck.
func _apply_chip_state(
	a_card: CommandableCard, a_transaction: PurchaseTransaction, a_queue: ProductionQueue
) -> void:
	if a_transaction.kind == PurchaseTransaction.Kind.BUILD and a_transaction.is_funded():
		a_card.set_glyph(GLYPH_IN_TRANSIT, COLOR_IN_TRANSIT)
		return
	match a_queue.blocker_for(a_transaction):
		ProductionQueue.Blocker.UNAFFORDABLE:
			a_card.set_glyph(GLYPH_UNAFFORDABLE, COLOR_UNAFFORDABLE)
		ProductionQueue.Blocker.NO_FREE_PRODUCER:
			a_card.set_glyph(GLYPH_NO_PRODUCER, COLOR_NO_PRODUCER)


## The head's live text: how much of the price is banked, and what it is waiting on.
func _refresh_head_text(a_queue: ProductionQueue) -> void:
	if _head == null or commander == null:
		return

	# A funded entry is PAID — purchases are charged at request time — so the cost readout has
	# nothing left to count down. What it is waiting for depends on its kind: a build wants its
	# builder to walk over, a unit wants a producer to come free.
	if _head.is_funded():
		_head_blocker.visible = false
		if a_queue.blocker_for(_head) == ProductionQueue.Blocker.NO_FREE_PRODUCER:
			_head_detail.text = "paid  ·  no free producer"
			return
		_head_detail.text = (
			"paid  ·  waiting on its builder"
			if _head.kind == PurchaseTransaction.Kind.BUILD
			else "paid  ·  starting"
		)
		return

	var cost: int = maxi(_head.energy_cost, _head.dominion_cost)
	var banked: int = commander.energy if _head.energy_cost > 0 else commander.dominion
	_head_detail.text = "%d / %d" % [mini(banked, cost), cost]

	var blocker: ProductionQueue.Blocker = a_queue.blocker_for(_head)
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
func _build_producing_column(a_parent: Node) -> void:
	var column := _make_column(a_parent, "Producing", 1.0)
	_producing_column = column
	_producing_caption = _make_label(HEADER_FONT_SIZE, MUTED_COLOR)
	column.add_child(_producing_caption)
	_producing_cards = _make_flow("ProducingCards")
	column.add_child(_producing_cards)
	_producing_none = _make_none_label()
	column.add_child(_producing_none)


func _build_queued_column(a_parent: Node) -> void:
	var column := _make_column(a_parent, "Queued", QUEUE_COLUMN_STRETCH)
	_queued_column = column
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_queued_caption = _make_label(HEADER_FONT_SIZE, MUTED_COLOR)
	_queued_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_queued_caption)
	_clear_queued_button = _make_clear_button(
		"Cancel the one-off purchases shown here",
		(
			"Cancel every one-off purchase shown in this column; anything already reserved is"
			+ " refunded in full.\nStanding orders are left alone, so they start re-filling the"
			+ " queue behind this."
		)
	)
	_clear_queued_button.pressed.connect(_on_clear_queued_pressed)
	header.add_child(_clear_queued_button)
	column.add_child(header)
	# The head and the chips behind it share one row, which keeps the column one card high —
	# the strip's whole height in the global view, and what fits the Details pane.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(body)
	_build_head_panel(body)
	_chips = _make_flow("Chips")
	# In the pane the chips wrap in whatever the head leaves; in the strip they take their own.
	_chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL if is_scoped else Control.SIZE_FILL
	body.add_child(_chips)
	_queued_none = _make_none_label()
	column.add_child(_queued_none)


func _build_standing_column(a_parent: Node) -> void:
	var column := _make_column(a_parent, "Standing", 1.0)
	_standing_column = column
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var caption := _make_label(HEADER_FONT_SIZE, MUTED_COLOR)
	caption.text = "standing"
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(caption)
	_clear_standing_button = _make_clear_button(
		"Cancel the standing orders shown here",
		(
			"Cancel every standing order shown in this column, refunding anything already"
			+ " reserved.\nThe one-off queue is left alone. Nothing re-fills the queue from"
			+ " these afterwards, so idle income stops being spent on them."
		)
	)
	_clear_standing_button.pressed.connect(_on_clear_standing_pressed)
	header.add_child(_clear_standing_button)
	column.add_child(header)
	_standing_chips = _make_flow("StandingChips")
	column.add_child(_standing_chips)
	_standing_none = _make_none_label()
	column.add_child(_standing_none)


func _build_head_panel(a_parent: Node) -> void:
	# A container rather than a plain Control, so its width reaches the layout: the compact
	# strip is sized from its children's minimums.
	var row := HBoxContainer.new()
	row.name = "Head"
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_head_panel = row

	# A single-sided accent, so it reads as a marker on the row rather than as a border.
	_head_stripe = ColorRect.new()
	_head_stripe.custom_minimum_size = Vector2(2.0, 0.0)
	_head_stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_head_stripe)

	_head_card = CommandableCard.new()
	_head_card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_head_card)

	var text_column := VBoxContainer.new()
	text_column.add_theme_constant_override("separation", 0)
	text_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_head_name = _make_label(HEAD_NAME_FONT_SIZE, TEXT_COLOR)
	_head_detail = _make_label(HEADER_FONT_SIZE, MUTED_COLOR)
	_head_blocker = _make_label(HEADER_FONT_SIZE, COLOR_UNAFFORDABLE)
	text_column.add_child(_head_name)
	text_column.add_child(_head_detail)
	text_column.add_child(_head_blocker)
	row.add_child(text_column)

	a_parent.add_child(row)


func _make_column(a_parent: Node, a_name: String, a_stretch: float) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = a_name
	# Compact columns take only what their cards need; scoped ones share the pane.
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL if is_scoped else Control.SIZE_FILL
	column.size_flags_stretch_ratio = a_stretch
	column.add_theme_constant_override("separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	a_parent.add_child(column)
	return column


func _make_divider(a_parent: Node) -> Control:
	var line := ColorRect.new()
	line.color = DIVIDER_COLOR
	line.custom_minimum_size = Vector2(1.0, 0.0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	a_parent.add_child(line)
	return line


## Where a column's cards go: a wrapping flow in the scoped pane, one unwrapped row in the
## compact strip (a flow there would wrap to its narrowest, one card per line).
func _make_flow(a_name: String) -> Container:
	if not is_scoped:
		var row := HBoxContainer.new()
		row.name = a_name
		row.add_theme_constant_override("separation", 4)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return row
	var flow := HFlowContainer.new()
	flow.name = a_name
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return flow


func _make_none_label() -> Label:
	var label := _make_label(HEADER_FONT_SIZE, DIVIDER_COLOR)
	label.text = "none"
	return label


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
		if (
			not current.is_empty()
			and (current.front() as PurchaseTransaction).type != transaction.type
		):
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


## The clear buttons cancel what the column SHOWS: the whole tier in the global view, only the
## scoped producers' share in the scoped one — never something the player cannot see.
func _on_clear_queued_pressed() -> void:
	_cancel_each(_one_offs)


func _on_clear_standing_pressed() -> void:
	_cancel_each(_ring)


func _cancel_each(a_transactions: Array[PurchaseTransaction]) -> void:
	var queue: ProductionQueue = _queue()
	if queue == null or a_transactions.is_empty():
		return
	# One order on the scenario's stream, so a replay cancels them too
	# (recording-and-replay.md §The order stream); at once outside a scenario.
	var stream: OrderStream = OrderStream.of(self)
	if stream == null:
		for transaction: PurchaseTransaction in a_transactions.duplicate():
			queue.cancel(transaction)
		return
	var owner: int = a_transactions[0].commander.id if a_transactions[0].commander != null else 0
	stream.submit(
		PlayerOrder.new(
			PlayerOrder.Kind.CANCEL_PURCHASE,
			owner,
			{
				"owner": owner,
				"purchases": a_transactions.map(func(t: PurchaseTransaction) -> int: return t.id)
			}
		)
	)


## Detaches children immediately (so they aren't laid out for a stale frame) and frees them.
func _clear(a_container: Node) -> void:
	for child: Node in a_container.get_children():
		a_container.remove_child(child)
		child.queue_free()
#endregion
