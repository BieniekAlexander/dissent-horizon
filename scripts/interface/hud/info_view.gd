class_name InfoView
extends Control

## Drives the InfoSection's card display. Given the current selection each frame:
##   * Summary  — a single selected unit shows its name plus (generic) inventory details;
##     multiple units show one clickable CommandableCard each (left click re-selects that
##     unit alone, shift+click removes it from the selection).
##   * Details  — one CommandableCard per unit being trained by the selected producers,
##     plus, when a single unit with a Garrison is selected, one card per occupant
##     (left click evacuates that single occupant).
##   * Passives — one card per PASSIVE ability anything in the selection carries, greyed
##     while the commander has not unlocked it (see PassiveAbilityRow). The row hides itself
##     when the selection has none, so it costs nothing for the ordinary case.
##
## The panel is SELECTION-OWNED: with nothing selected it has nothing to say and is hidden
## entirely by the controller (see RTSController._update_selection_owned_panels), rather
## than repurposed. The global production queue it used to show in that state now lives in
## ProductionRail, which is on screen in every selection state — the queue readout was only
## ever reachable here by deselecting, which is the one thing a player in a fight never does.
##
## Cards are only rebuilt when their set actually changes (selection changes, a training
## job is queued/finishes, or a garrison's occupants change); the cards themselves
## self-refresh their bars every frame, so this stays cheap. The single-unit name/details
## label is refreshed every frame so live values (e.g. carried-item count) stay current.

## Requests the controller re-select `commandable` as the sole selection (summary card
## left click).
signal select_only_requested(commandable: Commandable)
## Requests the controller drop `commandable` from the current selection (summary card
## shift+left click).
signal deselect_requested(commandable: Commandable)
## Requests the controller ADD `commandable` to the current selection, keeping what is there
## — the additive reading of an occupant card's right click.
signal add_to_selection_requested(commandable: Commandable)
## Requests the controller select the PENDING units `transactions` will produce — a training
## job card's right click. The rail raises the same request for a queued purchase.
signal select_pending_requested(transactions: Array, additive: bool)
## Raised while the pointer is over an info widget that has ranges to draw, with the entity
## and the EntityRanges.Kind values it wants shown; and when it leaves. The controller owns
## the world-space indicator — this panel only says what is being asked about.
signal ranges_hovered(entity: Entity, kinds: Array)
signal ranges_unhovered()

@onready var _summary_name: Label = $Summary/NameLabel
@onready var _summary_cards: HFlowContainer = $Summary/Cards
@onready var _details_cards: HFlowContainer = $Details/Cards
## Optional: a scene that has not been given the row simply draws no passives, rather than
## failing to boot. Every other child here is required, because the panel is meaningless
## without them.
@onready var _passives: PassiveAbilityRow = get_node_or_null("Passives") as PassiveAbilityRow

## Optional in the same way and for the same reason: a scene without the row simply draws no
## per-piece figures. Its hover signals are re-emitted rather than connected through, so the
## controller has one panel to listen to rather than one per row.
@onready var _widgets: InfoWidgetRow = get_node_or_null("Widgets") as InfoWidgetRow

## Optional in the same way: what is TRUE of the single selected piece — effects acting on
## it, and what it is producing. Its
## hover signals are re-emitted with the widget row's, so the controller listens to the
## panel rather than to each row.
@onready var _effects: ConditionRow = get_node_or_null("Conditions") as ConditionRow

## The controller, for the one thing the panel cannot answer itself: whether a job card's
## unit is currently selected. Injected by RTSController, the same way the rail's is; null
## simply means no borders are painted.
var controller: RTSController = null

var _summary_sig: String = ""
var _details_sig: String = ""


func _ready() -> void:
	for row: Node in [_widgets, _effects, _passives]:
		if row == null:
			continue
		row.ranges_hovered.connect(func(a_entity: Entity, a_kinds: Array) -> void:
			ranges_hovered.emit(a_entity, a_kinds))
		row.ranges_unhovered.connect(func() -> void: ranges_unhovered.emit())

## Called every frame by the controller with the current selection. [a_commander] is the
## local player's, and only the passive row reads it — whether a standing benefit has been
## PAID for is a fact about the commander, not about the piece carrying it.
func update(a_selection: Array, a_commander: Commander = null) -> void:
	if _widgets != null:
		_widgets.update(a_selection)
	if _effects != null:
		_effects.update(a_selection)
	_update_summary(a_selection)
	_update_details(a_selection)
	_refresh_pending_borders()
	if _passives != null:
		_passives.update(a_selection, a_commander)

## The specific queued unit whose production card the mouse is currently over, as
## [producer, job_index] — empty when nothing is hovered. Read every frame by
## RTSController's rally indicator, which prefers this unit's own pre-issued commands
## over the head-of-queue rally it would otherwise draw for `producer`. A linear scan
## over the (few) visible details cards; cheap enough to run unconditionally.
func hovered_training_target() -> Array:
	for card: Node in _details_cards.get_children():
		var c := card as CommandableCard
		if c != null and c.is_hovered_training():
			return [c.training_producer(), c.training_job_index()]
	return []

func _update_summary(a_selection: Array) -> void:
	var commandables: Array = []
	var sig: String = ""
	for node: Node in a_selection:
		var c: Commandable = node as Commandable
		if c == null:
			continue
		commandables.append(c)
		sig += str(c.get_instance_id()) + "|"

	# The single-unit name+details label is cheap to rebuild, and its inventory line can
	# change without the selection changing, so refresh it every frame (outside the sig
	# gate that guards the more expensive card rebuilds).
	if commandables.size() == 1:
		_summary_name.text = _single_unit_text(commandables[0] as Commandable)

	if sig == _summary_sig:
		return
	_summary_sig = sig

	# A single selected unit shows its name/details as text; multiple units show a
	# clickable card each.
	_clear(_summary_cards)
	if commandables.size() == 1:
		_summary_name.visible = true
		_summary_cards.visible = false
	elif commandables.size() > 1:
		_summary_name.visible = false
		_summary_cards.visible = true
		for c: Commandable in commandables:
			var card := CommandableCard.new()
			_summary_cards.add_child(card)
			card.bind_existing(c, true)
			card.activated.connect(_on_summary_card_activated)
	else:
		_summary_name.visible = true
		_summary_cards.visible = false

## Generic single-unit blurb: the unit's node name, its flavor text (description, or
## verbose while ui_verbose is held — see Commandable.resolved_description/verbose), an
## HP line when it has a Defense component, an occupancy line when it has a Garrison
## (occupancy held vs capacity — in occupancy_size, not head count, so a bulky occupant
## reads as the room it takes), and its production line when it has a Production component.
func _single_unit_text(a_commandable: Commandable) -> String:
	var text: String = ""
	# NAME, FLAVOUR AND HIT POINTS BELONG TO THE WIDGET ROW where there is one — it says them
	# as figures with tooltips, which is strictly more than this label can. Repeating them
	# here would put the same three facts on screen twice, two lines apart. A scene without
	# the row (a HUD preview, a test harness) still gets them, since otherwise it would get
	# nothing at all.
	if _widgets == null:
		text = String((a_commandable as Node).name)
		text += "\n" + (
			a_commandable.resolved_verbose() if Input.is_action_pressed("ui_verbose")
			else a_commandable.resolved_description()
		)
		if a_commandable.defense != null:
			text += "\nHP %d/%d" % [
				roundi(a_commandable.defense.hp), roundi(a_commandable.defense.hp_max)
			]
	var garrison: Garrison = a_commandable.get_node_or_null("Garrison") as Garrison
	if garrison != null:
		text += "\nHolding %d/%d" % [garrison.occupied_size(), garrison.capacity]
	# NO ability lines here. Charges and the countdown to the next one live on the ABILITY'S OWN
	# BUTTON (see CommandButtonState / VerboseTooltipButton.show_availability): they answer "can
	# I press this", so they belong on the thing being pressed rather than in a summary the
	# player has to look away to read.
	if a_commandable.production != null:
		text += "\n" + _production_line(a_commandable)
	return text

## What a selected producer is doing, and how much of the commander's queue is pointed at it.
##
## "One structure builds one unit at a time" is a genuinely surprising rule for anyone
## arriving from another RTS — a barracks that looks like it is doing one thing while four
## more units are on order reads as broken. Naming the queued count is what separates "this
## building is idle" from "this building is working through a line", and it is the only place
## the global queue's per-structure share is visible while something IS selected (the
## ProductionRail shows the queue, but not whose it is).
##
## Read off the structure's own commander rather than an injected one: the panel already has
## the entity, and a producer always knows who owns it.
func _production_line(a_commandable: Commandable) -> String:
	var line: String = "Idle"
	if a_commandable.production.job_count() > 0:
		var building: Variant = a_commandable.production.job_type(0)
		line = "Building %s" % String(building) if building != null else "Building"

	var commander: Commander = a_commandable.commander
	if commander == null:
		return line
	var waiting: int = commander.production_queue.pending_count_for(a_commandable)
	if waiting <= 0:
		return line
	# "can land here", not "queued here": the queue is commander-global, so these purchases are
	# eligible at this structure rather than owned by it, and another producer may take them
	# first. Claiming otherwise would re-suggest the per-structure queues that were removed.
	return "%s  ·  %d more can land here" % [line, waiting]

## Left click on a summary card: shift removes that unit from the selection; a plain
## click makes it the sole selection. The controller applies the change, and the next
## update() rebuilds the cards to match.
func _on_summary_card_activated(a_commandable: Commandable, a_shift_held: bool) -> void:
	if a_shift_held:
		deselect_requested.emit(a_commandable)
	else:
		select_only_requested.emit(a_commandable)

func _update_details(a_selection: Array) -> void:
	# Flatten every training job of every selected producer into [producer, index], and —
	# for a single selected unit with a Garrison — every occupant into [host, occupant].
	var jobs: Array = []
	var occupants: Array = []
	var sig: String = ""

	for node: Node in a_selection:
		var c: Commandable = node as Commandable
		# Only the player's own units reveal their training queue / occupants — never an
		# enemy/neutral unit's.
		if c == null or c.commander_id != RTSController.PLAYER_COMMANDER_ID:
			continue
		if c.production != null:
			for i in c.production.job_count():
				jobs.append([c, i])
				sig += "job:%d:%s|" % [c.get_instance_id(), c.production.job_type(i)]

	# Garrison occupants only when exactly one unit is selected (single-unit detail view).
	if a_selection.size() == 1:
		var host: Commandable = a_selection[0] as Commandable
		if host != null and host.commander_id == RTSController.PLAYER_COMMANDER_ID:
			var garrison: Garrison = host.get_node_or_null("Garrison") as Garrison
			if garrison != null:
				for occupant: Commandable in garrison.occupants():
					occupants.append([host, occupant])
					sig += "occ:%d:%d|" % [host.get_instance_id(), occupant.get_instance_id()]

	if sig == _details_sig:
		return
	_details_sig = sig

	_clear(_details_cards)
	for job: Array in jobs:
		var card := CommandableCard.new()
		_details_cards.add_child(card)
		card.bind_training(job[0], job[1])
		# RIGHT click selects the unit being built. It has left the production queue, so the rail
		# cannot offer it — this card is the only place it can be reached.
		card.pending_selected.connect(_on_training_card_pending_selected)
	for entry: Array in occupants:
		var occ_card := CommandableCard.new()
		_details_cards.add_child(occ_card)
		occ_card.bind_existing(entry[1] as Commandable, true)
		# Bind the host so the click knows which garrison to evacuate from.
		occ_card.activated.connect(_on_occupant_card_activated.bind(entry[0] as Commandable))
		# RIGHT click SELECTS the occupant instead of evacuating it, so the player can give it
		# orders it carries out when it comes out. See
		# gdd/systems/ux/ui/control-matrices.md §Context 6.
		occ_card.select_requested.connect(_on_occupant_select_requested)

## Paint the green border on every job card whose unit is selected. Every frame rather than
## on the rebuild gate, because the SELECTION changes without the card set changing — the
## cards are the same, and which of them is picked is not.
func _refresh_pending_borders() -> void:
	if controller == null:
		return
	for node: Node in _details_cards.get_children():
		var card := node as CommandableCard
		if card == null or card.training_producer() == null:
			continue
		var production: Production = card.training_producer().production
		var transaction: PurchaseTransaction = production.job_transaction(card.training_job_index()) \
			if production != null else null
		card.set_pending_selected(controller.is_pending_selected(transaction))


## Right click on a training-job card: select the unit it is building. Routed to the same
## controller call the production rail uses, so a phantom is selected one way however it was
## pointed at.
func _on_training_card_pending_selected(
	a_transactions: Array, a_additive: bool, _a_all_of_type: bool
) -> void:
	select_pending_requested.emit(a_transactions, a_additive)


## Right click on a garrison-occupant card: select it. Routed through the same signals the
## summary cards use, so the controller has one way to be told "select this" — the additive
## reading is the one it has everywhere else.
func _on_occupant_select_requested(a_occupant: Commandable, a_additive: bool) -> void:
	if a_additive:
		add_to_selection_requested.emit(a_occupant)
	else:
		select_only_requested.emit(a_occupant)


## Left click on a garrison-occupant card evacuates that single occupant from `host`.
## Mirrors the training card cancelling its job directly; the next update() rebuilds the
## occupant cards once the garrison's occupant set changes.
##
## Gated on Garrison.can_release_occupant — the EXIT question, and only for the host's own
## side: a Servant riding a Stock Truck can be let out, the captives beside it cannot.
func _on_occupant_card_activated(
	a_occupant: Commandable, _a_shift_held: bool, a_host: Commandable
) -> void:
	if not is_instance_valid(a_host) or not is_instance_valid(a_occupant):
		return
	var garrison: Garrison = a_host.get_node_or_null("Garrison") as Garrison
	if garrison != null and garrison.can_release_occupant(a_occupant):
		garrison.evacuate_one(a_occupant, a_host.map)


## Detaches children immediately (so they aren't laid out for a stale frame) and
## frees them.
func _clear(a_container: Node) -> void:
	for child: Node in a_container.get_children():
		a_container.remove_child(child)
		child.queue_free()
