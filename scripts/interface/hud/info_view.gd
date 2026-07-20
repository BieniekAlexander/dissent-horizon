class_name InfoView
extends Control

## Drives the InfoSection's card display. Given the current selection each frame:
##   * Summary  — a single selected unit shows its name plus (generic) inventory details;
##     multiple units show one clickable CommandableCard each (left click re-selects that
##     unit alone, shift+click removes it from the selection).
##   * Details  — one CommandableCard per unit being trained by the selected producers,
##     plus, when a single unit with a Garrison is selected, one card per occupant
##     (left click evacuates that single occupant).
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

@onready var _summary_name: Label = $Summary/NameLabel
@onready var _summary_cards: HFlowContainer = $Summary/Cards
@onready var _details_cards: HFlowContainer = $Details/Cards

var _summary_sig: String = ""
var _details_sig: String = ""

## Called every frame by the controller with the current selection.
func update(selection: Array) -> void:
	_update_summary(selection)
	_update_details(selection)

func _update_summary(selection: Array) -> void:
	var commandables: Array = []
	var sig: String = ""
	for node: Node in selection:
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
	# clickable card each; nothing selected shows nothing.
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
		_summary_name.text = ""
		_summary_name.visible = false
		_summary_cards.visible = false

## Generic single-unit blurb: the unit's node name, an HP line when it has a Defense
## component, plus an inventory line when it has an Inventory component (carried items vs
## capacity, and its ability count).
func _single_unit_text(commandable: Commandable) -> String:
	var text: String = String((commandable as Node).name)
	if commandable.defense != null:
		text += "\nHP %d/%d" % [roundi(commandable.defense.hp), roundi(commandable.defense.hp_max)]
	var inventory: Inventory = commandable.get_node_or_null("Inventory") as Inventory
	if inventory != null:
		text += "\nCarrying %d/%d" % [inventory.item_count(), inventory.item_capacity]
		if not inventory.tool_specs.is_empty():
			text += "  ·  Abilities: %d" % inventory.tool_specs.size()
	return text

## Left click on a summary card: shift removes that unit from the selection; a plain
## click makes it the sole selection. The controller applies the change, and the next
## update() rebuilds the cards to match.
func _on_summary_card_activated(commandable: Commandable, shift_held: bool) -> void:
	if shift_held:
		deselect_requested.emit(commandable)
	else:
		select_only_requested.emit(commandable)

func _update_details(selection: Array) -> void:
	# Flatten every training job of every selected producer into [producer, index], and —
	# for a single selected unit with a Garrison — every occupant into [host, occupant].
	var jobs: Array = []
	var occupants: Array = []
	var sig: String = ""
	for node: Node in selection:
		var c: Commandable = node as Commandable
		# Only the player's own units reveal their training queue / occupants — never an
		# enemy/neutral unit's.
		if c == null or c.commander_id != RTSController.PLAYER_COMMANDER_ID:
			continue
		if c.production != null:
			for i in c.production.job_count():
				jobs.append([c, i])
				sig += "job:%d:%s|" % [c.get_instance_id(), c.production.job_scene(i).resource_path]

	# Garrison occupants only when exactly one unit is selected (single-unit detail view).
	if selection.size() == 1:
		var host: Commandable = selection[0] as Commandable
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
	for entry: Array in occupants:
		var occ_card := CommandableCard.new()
		_details_cards.add_child(occ_card)
		occ_card.bind_existing(entry[1] as Commandable, true)
		# Bind the host so the click knows which garrison to evacuate from.
		occ_card.activated.connect(_on_occupant_card_activated.bind(entry[0] as Commandable))

## Left click on a garrison-occupant card evacuates that single occupant from `host`.
## Mirrors the training card cancelling its job directly; the next update() rebuilds the
## occupant cards once the garrison's occupant set changes.
func _on_occupant_card_activated(occupant: Commandable, _shift_held: bool, host: Commandable) -> void:
	if not is_instance_valid(host) or not is_instance_valid(occupant):
		return
	var garrison: Garrison = host.get_node_or_null("Garrison") as Garrison
	if garrison != null:
		garrison.evacuate_one(occupant, host.map)

## Detaches children immediately (so they aren't laid out for a stale frame) and
## frees them.
func _clear(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
