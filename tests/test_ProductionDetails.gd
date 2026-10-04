extends GutTest

## The production readout (ProductionRail) in both of its places: the GLOBAL copy that holds the
## bottom-centre slot while nothing is selected, and the SCOPED copy in the info panel's
## Details pane, which shows only what the PRODUCTION page's producers are making, have queued
## and stand ready to refill. See gdd/systems/ux/ui/hud-layout.md §Production.
##
## Built out of tree the way test_ProductionQueue is: a bare Commander and Commandables
## carrying a Production component. Purchases are priced explicitly and the commander holds no
## energy, so every purchase stays QUEUED rather than being dispatched.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gtest=res://tests/test_ProductionDetails.gd -gexit

const TRAINEE_A: StringName = &"fake_trainee_a"
const TRAINEE_B: StringName = &"fake_trainee_b"
const PRICE: int = 10
## Long enough that a job enqueued here is still running when the test reads it.
const JOB_TICKS: int = 100


func _commander() -> Commander:
	return autofree(Commander.new()) as Commander


## An out-of-tree producer of `a_types`, its `production` wired by hand (the @onready never
## resolves outside the tree).
func _producer(a_types: Array[StringName]) -> Commandable:
	var producer := autofree(Commandable.new()) as Commandable
	var production := Production.new()
	production.producible_types = a_types
	producer.add_child(production)
	producer.production = production
	return producer


func _tool(a_type: StringName) -> Tool:
	return Tool.new("command_tool_%s" % a_type, a_type, null, str(a_type), Vector2i.ZERO, 0, 0)


func _purchase(
	a_commander: Commander, a_type: StringName, a_producers: Array, a_is_standing: bool = false
) -> PurchaseTransaction:
	var transaction := PurchaseTransaction.for_cost(
		a_commander, PurchaseTransaction.Kind.TRAIN, _tool(a_type), PRICE
	)
	transaction.dispatch_filter.assign(a_producers)
	transaction.standing = a_is_standing
	return a_commander.production_queue.submit(transaction)


func _rail(a_commander: Commander, a_is_scoped: bool, a_scope: Array = []) -> ProductionRail:
	var rail := ProductionRail.new()
	rail.is_scoped = a_is_scoped
	add_child_autofree(rail)
	rail.commander = a_commander
	rail.set_scope(a_scope)
	rail._refresh()
	return rail


func _queued_types(a_rail: ProductionRail) -> Array:
	return a_rail._one_offs.map(func(t: PurchaseTransaction) -> StringName: return t.type)


# --- What is in scope ---------------------------------------------------------------


func test_a_purchase_is_in_scope_when_it_could_land_on_a_scoped_producer() -> void:
	var commander := _commander()
	var a := _producer([TRAINEE_A])
	var b := _producer([TRAINEE_B])
	var purchase := _purchase(commander, TRAINEE_A, [a, b])
	assert_true(ProductionRail.is_in_scope(purchase, [a]))
	assert_false(ProductionRail.is_in_scope(purchase, [b]), "b cannot make it")


func test_a_build_is_never_in_scope() -> void:
	var commander := _commander()
	var a := _producer([TRAINEE_A])
	var build := PurchaseTransaction.for_cost(
		commander, PurchaseTransaction.Kind.BUILD, _tool(TRAINEE_A), PRICE
	)
	assert_false(ProductionRail.is_in_scope(build, [a]))


# --- The scoped copy ----------------------------------------------------------------


func test_the_scoped_queue_holds_only_what_its_producers_could_make() -> void:
	var commander := _commander()
	var a := _producer([TRAINEE_A])
	var b := _producer([TRAINEE_B])
	_purchase(commander, TRAINEE_B, [b])
	_purchase(commander, TRAINEE_A, [a])
	_purchase(commander, TRAINEE_A, [a])
	var rail := _rail(commander, true, [a])
	assert_eq(_queued_types(rail), [TRAINEE_A, TRAINEE_A])
	assert_eq(rail._head.type, TRAINEE_A, "the head is the first IN SCOPE, not the queue's")


func test_the_scoped_standing_ring_is_filtered_too() -> void:
	var commander := _commander()
	var a := _producer([TRAINEE_A])
	var b := _producer([TRAINEE_B])
	_purchase(commander, TRAINEE_A, [a], true)
	_purchase(commander, TRAINEE_B, [b], true)
	var rail := _rail(commander, true, [b])
	assert_eq(rail._ring.size(), 1)
	assert_eq(rail._ring[0].type, TRAINEE_B)


func test_the_producing_column_shows_each_busy_scoped_producer() -> void:
	var commander := _commander()
	var busy := _producer([TRAINEE_A])
	var idle := _producer([TRAINEE_A])
	var outside := _producer([TRAINEE_A])
	busy.production.enqueue(JOB_TICKS, null, TRAINEE_A)
	outside.production.enqueue(JOB_TICKS, null, TRAINEE_A)
	var rail := _rail(commander, true, [busy, idle])
	var cards: Array = rail._producing_cards.get_children()
	assert_eq(cards.size(), 1, "the idle producer has no job, the outside one is not in scope")
	assert_eq((cards[0] as CommandableCard).training_producer(), busy)
	assert_eq(rail._producing_caption.text, "producing  ·  1 / 2")


func test_an_empty_scoped_panel_still_shows_with_every_column() -> void:
	var commander := _commander()
	var rail := _rail(commander, true, [_producer([TRAINEE_A])])
	assert_true(rail.visible, "the player opened the page to ask; 'none' is the answer")
	for column: Control in [rail._producing_column, rail._queued_column, rail._standing_column]:
		assert_true(column.visible, column.name)


func test_clearing_a_scoped_column_cancels_only_what_it_shows() -> void:
	var commander := _commander()
	var a := _producer([TRAINEE_A])
	var b := _producer([TRAINEE_B])
	var kept := _purchase(commander, TRAINEE_B, [b])
	_purchase(commander, TRAINEE_A, [a])
	var rail := _rail(commander, true, [a])
	rail._on_clear_queued_pressed()
	assert_eq(commander.production_queue.queued(), [kept] as Array[PurchaseTransaction])


# --- The global copy ----------------------------------------------------------------


func test_the_global_queue_holds_everything() -> void:
	var commander := _commander()
	_purchase(commander, TRAINEE_B, [_producer([TRAINEE_B])])
	_purchase(commander, TRAINEE_A, [_producer([TRAINEE_A])])
	var rail := _rail(commander, false)
	assert_eq(_queued_types(rail), [TRAINEE_B, TRAINEE_A])


func test_the_global_panel_hides_with_nothing_to_say() -> void:
	var rail := _rail(_commander(), false)
	assert_false(rail.visible)


func test_the_global_panel_drops_its_empty_columns() -> void:
	var commander := _commander()
	_purchase(commander, TRAINEE_A, [_producer([TRAINEE_A])])
	var rail := _rail(commander, false)
	assert_true(rail.visible)
	assert_true(rail._queued_column.visible)
	assert_false(rail._producing_column.visible, "nothing is being made")
	assert_false(rail._standing_column.visible, "nothing is standing")


func test_an_inactive_panel_hides_whatever_it_holds() -> void:
	var commander := _commander()
	_purchase(commander, TRAINEE_A, [_producer([TRAINEE_A])])
	var rail := _rail(commander, false)
	rail.is_active = false
	rail._refresh()
	assert_false(rail.visible, "the controller turns it off while something is selected")


func test_the_global_panel_is_a_strip_hugging_the_bottom_of_its_slot() -> void:
	var commander := _commander()
	_purchase(commander, TRAINEE_A, [_producer([TRAINEE_A])])
	var slot := Control.new()
	slot.size = Vector2(1000.0, 400.0)
	add_child_autofree(slot)
	var rail := ProductionRail.new()
	rail.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	slot.add_child(rail)
	rail.commander = commander
	rail._refresh()
	var expected: Vector2 = (
		rail._columns.get_combined_minimum_size() + Vector2.ONE * 2.0 * ProductionRail.PADDING
	)
	assert_eq(rail.size, expected, "as big as its cards, no bigger")
	assert_lt(rail.size.y, slot.size.y / 2.0, "a strip, not the slot")
	assert_eq(rail.position.y + rail.size.y, slot.size.y, "pinned to the bottom")
	assert_almost_eq(rail.position.x + rail.size.x / 2.0, slot.size.x / 2.0, 0.5, "centred")
