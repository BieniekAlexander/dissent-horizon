class_name StaggeredCardRow
extends Control

## One row of a multi-selection: every selected piece of ONE type, as a fanned stack of cards.
##
## The first card is drawn whole; each card after it is tucked BEHIND the one before, showing
## only its right-hand columns (HP, dials, garrison) plus a margin. Every card is staggered by
## the same stride whether or not its columns have anything in them, so the stack reads as an
## even fan and a gap never means "this one is different". See
## gdd/systems/ux/ui/actor-cards.md §A multi-selection.

## What each tucked card shows past its columns — enough of the picture's edge to see where one
## card ends and the next begins.
const STRIDE_MARGIN: float = 3.0

## The cards in the order they were given — the first is the whole one on top.
var _cards: Array[Control] = []


func _init() -> void:
	# The row only places cards; the cards take the clicks.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The horizontal step between cards `a_card_size` big: their two columns plus the margin.
static func stride_for(a_card_size: Vector2) -> float:
	return CommandableCard.column_strip_width(a_card_size.y) + STRIDE_MARGIN


## How many cards fit across `a_width`: the whole first one, then a stride per card after it.
## At least one, so a pane narrower than a card still shows something.
static func capacity_for(a_width: float, a_card_size: Vector2) -> int:
	if a_width <= a_card_size.x:
		return 1
	return 1 + int((a_width - a_card_size.x) / stride_for(a_card_size))


## Add `a_card` at the back of the fan. It goes FIRST among the children, because a later child
## draws over an earlier one and the fan's first card must be on top — which also makes it
## what a click on the overlap hits.
func add_card(a_card: Control) -> void:
	_cards.append(a_card)
	add_child(a_card)
	move_child(a_card, 0)
	_layout()


func cards() -> Array[Control]:
	return _cards


func _layout() -> void:
	if _cards.is_empty():
		custom_minimum_size = Vector2.ZERO
		return
	# A card sizes itself in _ready, which has not run on one built outside the tree.
	var card_size: Vector2 = _cards[0].custom_minimum_size
	if card_size == Vector2.ZERO:
		card_size = CommandableCard.CARD_SIZE
	var stride: float = stride_for(card_size)
	for i: int in _cards.size():
		_cards[i].position = Vector2(i * stride, 0.0)
	custom_minimum_size = Vector2(card_size.x + (_cards.size() - 1) * stride, card_size.y)
