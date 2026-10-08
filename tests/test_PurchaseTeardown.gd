extends GutTest

## A build order released after its commander is gone must not touch that commander.
##
## It happens only at teardown: commanders are freed one after another, and a unit held in a
## LATER commander's garrison is freed with that garrison — so its Build command drops, and
## releases its purchase, after its own commander no longer exists. Touching the freed commander
## there segfaulted every headless self-play process on exit. The fixture reproduces the chain
## from the command down: a FUNDED build purchase held by a live MoveCommand, whose last
## reference is dropped once the commander has been freed.

const ENERGY_COST: int = 40
const DOMINION_COST: int = 5


func _commander() -> Commander:
	var commander: Commander = Commander.new()
	add_child(commander)
	return commander


## A funded build purchase on `a_commander`, held by one command.
func _held_purchase(a_commander: Commander) -> Array:
	var transaction: PurchaseTransaction = PurchaseTransaction.for_cost(
		a_commander, PurchaseTransaction.Kind.BUILD, null, ENERGY_COST, DOMINION_COST
	)
	transaction.fund()
	var message: CommandMessage = CommandMessage.new(null)
	message.transaction = transaction
	return [transaction, MoveCommand.new(message)]


func test_dropping_the_last_holder_refunds_a_live_commander() -> void:
	# Live-game behaviour, unchanged: a builder killed before laying the foundation hands the
	# reserved cost back.
	var commander: Commander = _commander()
	var energy_before: int = commander.energy
	var held: Array = _held_purchase(commander)
	var transaction: PurchaseTransaction = held[0]
	held.clear()  # drops the command, the last holder
	assert_eq(transaction.state, PurchaseTransaction.State.CANCELLED)
	assert_eq(commander.energy, energy_before, "the reserved cost came back")
	commander.free()


func test_dropping_the_last_holder_after_the_commander_is_freed_is_harmless() -> void:
	var commander: Commander = _commander()
	var held: Array = _held_purchase(commander)
	var transaction: PurchaseTransaction = held[0]
	commander.free()
	held.clear()
	assert_eq(
		transaction.state,
		PurchaseTransaction.State.CANCELLED,
		"still cancelled, with the refund owed to nobody"
	)


func test_a_blueprint_freed_first_is_discarded_quietly() -> void:
	var commander: Commander = _commander()
	var transaction: PurchaseTransaction = PurchaseTransaction.for_cost(
		commander, PurchaseTransaction.Kind.BUILD, null, ENERGY_COST
	)
	var blueprint: Actor = Actor.new()
	transaction.planned_structure = blueprint
	blueprint.free()
	transaction.discard_planned_structure()
	assert_null(transaction.planned_structure)
	commander.free()
