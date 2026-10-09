class_name MatchSummaryView
extends PanelContainer

## A match's summary — units and structures each commander made, in total and per piece — drawn
## from the match's EVENT
## LOG and nothing else (MatchSummary over MatchLog.events), so it shows the same numbers
## whether the log is live or read back from a file. Shown in the pause menu while the debug
## view is up, and by Scenario when a match ends.

## The close button was pressed. Only offered when `is_closable`.
signal closed

const HEADERS: Array[String] = ["Commander", "Units trained", "Structures built"]
## The breakdown's sections: the key MatchSummary.created_by_piece files them under, and heading.
const SECTIONS: Array[Array] = [["units", "Units trained"], ["structures", "Structures built"]]

## Whether the view offers its own close button: yes standing alone at a match's end; no inside
## the pause menu, which closes with the menu.
@export var is_closable: bool = false

@onready var _title: Label = %Title
@onready var _table: GridContainer = %Table
@onready var _breakdown: GridContainer = %Breakdown
@onready var _source: Label = %Source
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_close_button.visible = is_closable
	_close_button.pressed.connect(func() -> void: closed.emit())


## Show `a_log`'s summary under `a_title`.
func present(a_log: MatchLog, a_title: String) -> void:
	show_events(a_log.events, a_title)


## Show the summary of `a_events`, an event log oldest first, under `a_title`.
func show_events(a_events: Array, a_title: String) -> void:
	_title.text = a_title
	for child: Node in _table.get_children():
		_table.remove_child(child)
		child.queue_free()
	for header: String in HEADERS:
		_add_cell(header)
	var counts: Dictionary = MatchSummary.created_counts(a_events)
	var winner: int = MatchSummary.winner(a_events)
	var ids: Array = counts.keys()
	ids.sort()
	for id: int in ids:
		_add_cell("Commander %d%s" % [id, "  (winner)" if id == winner else ""])
		_add_cell(str(counts[id]["units"]))
		_add_cell(str(counts[id]["structures"]))
	_fill_breakdown(MatchSummary.created_by_piece(a_events), ids)
	_source.text = "From the match event log: %d events" % a_events.size()


## Put `a_control` at the foot of the summary, above the close button — the end of a match
## adds its Save replay form here.
func add_footer(a_control: Control) -> void:
	_close_button.add_sibling(a_control)
	_close_button.get_parent().move_child(a_control, _close_button.get_index())


## The text of every table cell, row by row, headers first.
func cell_texts() -> Array[String]:
	var out: Array[String] = []
	for child: Node in _table.get_children():
		out.append((child as Label).text)
	return out


## The breakdown table's cells, row by row: each section's heading row, then its pieces.
func breakdown_texts() -> Array[String]:
	var out: Array[String] = []
	for child: Node in _breakdown.get_children():
		out.append((child as Label).text)
	return out


func _add_cell(a_text: String) -> void:
	_table.add_child(_label(a_text))


## One table, so the commander columns line up down it: per section, a heading row naming the
## commanders, then a row per piece any commander made, the pieces made most first.
func _fill_breakdown(a_by_piece: Dictionary, a_ids: Array) -> void:
	for child: Node in _breakdown.get_children():
		_breakdown.remove_child(child)
		child.queue_free()
	_breakdown.columns = 1 + a_ids.size()
	for section: Array in SECTIONS:
		_breakdown.add_child(_label(section[1]))
		for id: int in a_ids:
			_breakdown.add_child(_label("Commander %d" % id))
		var totals: Dictionary = {}
		for id: int in a_ids:
			var made: Dictionary = a_by_piece[id][section[0]]
			for piece: String in made:
				totals[piece] = totals.get(piece, 0) + made[piece]
		var pieces: Array = totals.keys()
		pieces.sort_custom(
			func(a: String, b: String) -> bool:
				return totals[a] > totals[b] or (totals[a] == totals[b] and a < b)
		)
		if pieces.is_empty():
			_add_row(["  none"], a_ids.size())
		for piece: String in pieces:
			var row: Array = ["  " + piece]
			for id: int in a_ids:
				row.append(str(a_by_piece[id][section[0]].get(piece, 0)))
			_add_row(row, a_ids.size())


## One breakdown row: `a_cells`, padded with blanks to a cell per commander.
func _add_row(a_cells: Array, a_commanders: int) -> void:
	for i: int in 1 + a_commanders:
		_breakdown.add_child(_label(a_cells[i] if i < a_cells.size() else ""))


static func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label
