class_name CargoSlotBinding
extends ControlBinding

## One slot of an armed sanction's CARGO MENU — the Drop's choice of what the transport
## carries. Slot `n` stands for the armed level's `n`-th payload piece, so the button's face
## is not fixed: RTSController draws the piece and its count onto it while the menu is up.
##
## A binding of its own rather than the piece's train button, which is what the menu used to
## reuse, and that reuse is why the menu never appeared. A train button lives on the
## PRODUCTION card at its producer's cell, so with a caster selected it was filtered off the
## ACTIVE card the menu opens on — and two pieces from two producers (the Recruit and the
## Sloop) share a training cell, so at most one of them could ever be drawn.
##
## The cell is the slot's position in the payload list, left to right along row 0, and a
## level lists its pieces in the same order as the level below it, so a piece keeps its key
## when the sanction is upgraded. On the ACTIVE card, like Build's structure list, and arming a
## cargo sanction turns the grid to it from whichever card armed it (RTSController
## ._on_deploy_button_pressed).
##
## Not an order to the selection, so the prefix is not `command_` — like a producer's
## context button, pressing it changes what the card has chosen and nothing in the world.

const PREFIX: String = "card_cargo_"

## Which payload this slot stands for, counted from 0.
var slot: int


func _init(a_slot: int) -> void:
	super(
		PREFIX + str(a_slot),
		"Cargo %d" % (a_slot + 1),
		Vector2i(a_slot, 0),
		ControlContext.CARGO,
		"Choose this cargo",
		"",
		CommandFamily.ACTIVE
	)
	slot = a_slot


## The slot a command name stands for, or -1 when it is not a cargo slot at all.
static func slot_of(a_command_name: String) -> int:
	if not a_command_name.begins_with(PREFIX):
		return -1
	var index: String = a_command_name.trim_prefix(PREFIX)
	return int(index) if index.is_valid_int() else -1


## The command name of slot `slot`.
static func command_for_slot(slot: int) -> String:
	return PREFIX + str(slot)


#region Registry
## One per cell of row 0: a level offers at most a row of cargo (the importer refuses more,
## SpecRegistry._validate_payloads).
static var _bindings: Array = _build()


static func all() -> Array:
	return _bindings


static func _build() -> Array:
	var out: Array = []
	for i: int in GRID_WIDTH:
		out.append(CargoSlotBinding.new(i))
	return out
#endregion
