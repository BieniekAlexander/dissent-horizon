class_name ProducerContextBinding
extends ControlBinding

## A PRODUCER's radio button in row 0 of the PRODUCTION card: it picks whose training the card
## is showing, when the selection holds more than one kind of producer.
##
## The fourth kind of binding, and the only one that acts on the CARD rather than on the
## selection. Pressing it changes nothing in the world — which is why it has its own
## ControlContext and never reaches `process_command`.
##
## THE CELL IS STATIC, per producer piece id (`ui.context_grid`), and that is the whole design
## decision. Packing the row left per selection would move a war factory's button from W to Q
## depending on what else was picked up, and a key that trains one thing in one selection and
## another in the next is exactly what positional hotkeys exist to prevent. Left-alignment is
## an AUTHORING convention across a faction's producers — Colonial's Citadel, Barracks, War
## Factory and Airfield sit at Q W E R collectively — so a selection holding only the war
## factory shows one button at E with Q and W empty. That is correct and is never compacted.

## Command-name prefix. Not `command_` — that prefix routes into the grid's hotkey dispatcher
## as an order to the selection, and this is not one (see input-action-naming.md).
const PREFIX: String = "card_producer_"

## The producer piece whose training this button selects.
var producer_id: StringName
var faction: int


func _init(
	a_producer_id: StringName, a_label: String, a_grid_position: Vector2i, a_faction: int
) -> void:
	super(
		PREFIX + String(a_producer_id),
		a_label,
		a_grid_position,
		ControlContext.TRAIN,
		"Show what the %s can train" % a_label,
		(
			"Pick which of the selected producers this card is showing.\nOne is always "
			+ "chosen; the greyed one is the one you are looking at."
		),
		CommandFamily.PRODUCTION
	)
	producer_id = a_producer_id
	faction = a_faction


func faction_mask() -> int:
	return faction


## Only a selection holding THIS producer ever draws it, which is what lets two factions'
## context buttons share a cell.
func actor_ids() -> Array:
	return [producer_id]


#region Registry
## LAZY, not a static initialiser. `_build` reads the Tool registry, which is itself a static
## built on first reference — and a static var initialised at load time can run before it,
## which produced an empty row that nothing reported. Built on first call and cached after.
static var _bindings: Array = []


static func all() -> Array:
	if _bindings.is_empty():
		_bindings = _build()
	return _bindings


## One binding per producer that authors a context cell. Built from the Tool registry rather
## than from a table of its own: `producers` is already derived there from every `trains:`
## list, so a piece that stops training anything stops having a context button with no second
## place to update.
static func _build() -> Array:
	return from_tools(Tool.command_tool_map.values())


## The context buttons `tools` imply — split from _build so the spec importer can review a
## tool list it has not written yet.
static func from_tools(tools: Array) -> Array:
	var by_id: Dictionary = {}
	for tool: Tool in tools:
		by_id[tool.type] = tool
	var seen: Dictionary = {}
	var out: Array = []
	for tool: Tool in tools:
		for producer: Variant in tool.producers:
			var id: StringName = StringName(str(producer))
			if seen.has(id):
				continue
			seen[id] = true
			var piece: Tool = by_id.get(id)
			if piece == null or piece.context_grid.x < 0:
				continue
			out.append(
				ProducerContextBinding.new(
					id, piece.label, piece.context_grid, piece.faction_mask()
				)
			)
	return out
#endregion
