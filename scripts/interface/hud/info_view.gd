class_name InfoView
extends Control

## Drives the InfoSection's card display. Given the current selection each frame:
##   * Summary  — one CommandableCard per selected commandable (live units).
##   * Details  — one CommandableCard per unit being trained by those commandables.
##
## Cards are only rebuilt when their set actually changes (selection changes, or a
## training job is queued/finishes); the cards themselves self-refresh their bars
## every frame, so this stays cheap.

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

	if sig == _summary_sig:
		return
	_summary_sig = sig

	# A single selected unit shows its full name as text; multiple units show a
	# card each; nothing selected shows nothing.
	_clear(_summary_cards)
	if commandables.size() == 1:
		_summary_name.text = String((commandables[0] as Node).name)
		_summary_name.visible = true
		_summary_cards.visible = false
	elif commandables.size() > 1:
		_summary_name.visible = false
		_summary_cards.visible = true
		for c: Commandable in commandables:
			var card := CommandableCard.new()
			_summary_cards.add_child(card)
			card.bind_existing(c)
	else:
		_summary_name.text = ""
		_summary_name.visible = false
		_summary_cards.visible = false

func _update_details(selection: Array) -> void:
	# Flatten every training job of every selected producer into [producer, index].
	var jobs: Array = []
	var sig: String = ""
	for node: Node in selection:
		var c: Commandable = node as Commandable
		if c == null or c.production == null:
			continue
		for i in c.production.job_count():
			jobs.append([c, i])
			sig += "%d:%s|" % [c.get_instance_id(), c.production.job_scene(i).resource_path]

	if sig == _details_sig:
		return
	_details_sig = sig

	_clear(_details_cards)
	for job: Array in jobs:
		var card := CommandableCard.new()
		_details_cards.add_child(card)
		card.bind_training(job[0], job[1])

## Detaches children immediately (so they aren't laid out for a stale frame) and
## frees them.
func _clear(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
