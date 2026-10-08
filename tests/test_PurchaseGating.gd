extends GutTest

## Tests for REQUISITION MODE — the gate that decides whether an unaffordable purchase is
## QUEUED (and fulfilled when the resources arrive) or REFUSED outright.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_PurchaseGating.gd -gexit
##
## Three layers, tested separately because each can break without the others noticing:
##   * Commander.get_blocking_need(type, allow_deferral) — the gate itself;
##   * CommandMessage.defer_if_unaffordable → Train/Build.meets_precondition — the wiring
##     that carries the player's mode down to it;
##   * Actor.awaiting_funds → MeshVisual shade — the world-space tell that a
##     blueprint is queued rather than ready to start.
##
## Everything is built out of tree (a Commander that was never added to the scene, bare
## Commandables), the same way test_ProductionQueue.gd does it, and priced explicitly so
## nothing here rides on gdd-authored costs.

const TRAINEE: StringName = &"fake_trainee"
const GATED: StringName = &"fake_gated"
const PREREQ_STRUCTURE: StringName = &"fake_prerequisite"


func _make_commander(a_energy: int = 0) -> Commander:
	var commander := autofree(Commander.new()) as Commander
	commander.energy = a_energy
	# 20 energy, no infrastructure/dominion cost, 10 ticks, no structure prerequisite.
	commander.technology_mapping[TRAINEE] = TechnologySpec.new(20, 0, 0, 10)
	# Same price, but gated behind a structure the commander does not have — the
	# non-deferrable failure the gate must never swallow.
	commander.technology_mapping[GATED] = TechnologySpec.new(20, 0, 0, 10, [PREREQ_STRUCTURE])
	return commander


## A stand-in production structure owned by `a_commander`. Both components are assigned
## to their fields directly as well as added as children: the @onready shims never
## resolve out of tree, and `Entity.commander` delegates through the `ownership` one.
func _make_producer(a_types: Array[StringName], a_commander: Commander) -> Actor:
	var producer := autofree(Actor.new()) as Actor
	var production := Production.new()
	production.producible_types = a_types
	producer.add_child(production)
	producer.production = production
	var own := Ownership.new()
	own.name = "Ownership"
	producer.add_child(own)
	producer.ownership = own
	own.commander = a_commander
	return producer


func _make_tool(a_type: StringName) -> Tool:
	return Tool.new("command_tool_%s" % a_type, a_type, null, str(a_type), Vector2i.ZERO, 0, 0)


## A CommandMessage carrying `a_tool`, with the deferral flag the additive modifier stamps. `null`
## for the map is fine: nothing in a Train precondition touches it.
func _make_message(a_type: StringName, a_defer: bool) -> CommandMessage:
	var message := CommandMessage.new(null)
	message.tool = _make_tool(a_type)
	message.defer_if_unaffordable = a_defer
	return message


## --- the gate itself --------------------------------------------------------


func test_shortfall_is_waived_when_deferral_is_allowed() -> void:
	var commander := _make_commander(0)
	assert_eq(
		commander.get_blocking_need(TRAINEE, true),
		TechnologySpec.UnmetNeed.NONE,
		"an unaffordable purchase does not block the order with the modifier held"
	)


func test_shortfall_blocks_when_deferral_is_refused() -> void:
	var commander := _make_commander(0)
	assert_eq(
		commander.get_blocking_need(TRAINEE, false),
		TechnologySpec.UnmetNeed.NOT_ENOUGH_ENERGY,
		"with no modifier held the shortfall is a real blocking need"
	)


func test_affordable_purchase_passes_either_way() -> void:
	var commander := _make_commander(100)
	assert_eq(commander.get_blocking_need(TRAINEE, false), TechnologySpec.UnmetNeed.NONE)
	assert_eq(commander.get_blocking_need(TRAINEE, true), TechnologySpec.UnmetNeed.NONE)


func test_deferral_defaults_to_allowed() -> void:
	# The default is what every non-player caller relies on — scenario events, the bot's
	# actuator, and the tests that predate the gate.
	var commander := _make_commander(0)
	assert_eq(
		commander.get_blocking_need(TRAINEE),
		TechnologySpec.UnmetNeed.NONE,
		"omitting the argument keeps the original always-defer behavior"
	)


func test_missing_structure_blocks_regardless_of_deferral() -> void:
	# Waiting cannot resolve a missing prerequisite, so the gate must not swallow it in
	# either mode — this is the failure the modifier is NOT about.
	var commander := _make_commander(1000)
	assert_eq(
		commander.get_blocking_need(GATED, true),
		TechnologySpec.UnmetNeed.MISSING_STRUCTURE,
		"a tech prerequisite still blocks with the modifier held"
	)
	assert_eq(commander.get_blocking_need(GATED, false), TechnologySpec.UnmetNeed.MISSING_STRUCTURE)


## --- the wiring: message flag → precondition --------------------------------


func test_message_defaults_to_deferring() -> void:
	assert_true(
		CommandMessage.new(null).defer_if_unaffordable,
		"a message built outside the HUD defers, so scenario events are unaffected"
	)


func test_deep_copy_carries_the_flag() -> void:
	# Every builder in a multi-select build order gets its own snapshot of the order's
	# message; they must all agree about whether this purchase may wait.
	var message := _make_message(TRAINEE, false)
	assert_false(CommandMessage.deep_copy(message).defer_if_unaffordable)
	message.defer_if_unaffordable = true
	assert_true(CommandMessage.deep_copy(message).defer_if_unaffordable)


func test_train_precondition_allows_unaffordable_order_with_the_modifier() -> void:
	var commander := _make_commander(0)
	var producer := _make_producer([TRAINEE], commander)
	assert_eq(
		Train.meets_precondition(producer, _make_message(TRAINEE, true)),
		MoveCommand.PreconditionFailureCause.NONE,
		"the order is accepted and becomes a queued requisition"
	)


func test_train_precondition_refuses_unaffordable_order_without_the_modifier() -> void:
	var commander := _make_commander(0)
	var producer := _make_producer([TRAINEE], commander)
	assert_eq(
		Train.meets_precondition(producer, _make_message(TRAINEE, false)),
		MoveCommand.PreconditionFailureCause.NOT_ENOUGH_ENERGY,
		"without the mode, an unaffordable train is refused rather than silently queued"
	)


func test_train_precondition_accepts_affordable_order_without_the_modifier() -> void:
	var commander := _make_commander(100)
	var producer := _make_producer([TRAINEE], commander)
	assert_eq(
		Train.meets_precondition(producer, _make_message(TRAINEE, false)),
		MoveCommand.PreconditionFailureCause.NONE,
		"the gate only ever bites on a shortfall"
	)


## --- the tell: awaiting-funds shade -----------------------------------------


func test_shade_reflects_awaiting_funds() -> void:
	var blueprint := autofree(Actor.new()) as Actor
	assert_eq(blueprint.construction_shade(), MeshVisual.SHADE_NORMAL)
	blueprint.set_awaiting_funds(true)
	assert_eq(
		blueprint.construction_shade(),
		MeshVisual.SHADE_AWAITING_FUNDS,
		"a blueprint waiting on money is drawn darker"
	)


func test_funding_clears_the_awaiting_funds_shade() -> void:
	# The blueprint has no back-reference to its purchase; fund() is the one moment the
	# cost is committed, so it is what tells the blueprint to brighten.
	var commander := _make_commander(100)
	var blueprint := autofree(Actor.new()) as Actor
	blueprint.set_awaiting_funds(true)
	var transaction := PurchaseTransaction.for_cost(
		commander, PurchaseTransaction.Kind.BUILD, _make_tool(TRAINEE), 20
	)
	transaction.planned_structure = blueprint
	transaction.fund()
	assert_false(blueprint.awaiting_funds, "the site brightens as soon as it is paid for")
	assert_eq(blueprint.construction_shade(), MeshVisual.SHADE_NORMAL)
	# Don't let the transaction free the blueprint out from under autofree.
	transaction.planned_structure = null


func test_fund_on_a_transaction_with_no_blueprint_is_safe() -> void:
	# A TRAIN purchase never raises one, and so must not trip over the notification.
	var commander := _make_commander(100)
	var transaction := PurchaseTransaction.for_cost(
		commander, PurchaseTransaction.Kind.TRAIN, _make_tool(TRAINEE), 20
	)
	transaction.fund()
	assert_true(transaction.is_funded())


func test_mesh_visual_shade_roundtrips_and_clamps() -> void:
	var visual := autofree(MeshVisual.new()) as MeshVisual
	assert_eq(visual.shade(), MeshVisual.SHADE_NORMAL, "a fresh visual is undarkened")
	visual.set_shade(MeshVisual.SHADE_AWAITING_FUNDS)
	assert_eq(visual.shade(), MeshVisual.SHADE_AWAITING_FUNDS)
	visual.set_shade(-1.0)
	assert_eq(visual.shade(), 0.0, "clamped low")
	visual.set_shade(4.0)
	assert_eq(visual.shade(), 1.0, "clamped high")


## --- ordering at an unfunded blueprint --------------------------------------


## A blueprint whose own BUILD purchase is still PENDING can't produce anything until that
## structure is funded, built and finished. With no modifier held that order is refused,
## for the same reason an unaffordable one is: nothing about it can happen now.
func test_training_at_an_unfunded_blueprint_is_refused_without_the_modifier() -> void:
	var commander := _make_commander(1000)
	var blueprint := _make_producer([TRAINEE], commander)
	blueprint.set_awaiting_funds(true)
	assert_eq(
		Train.meets_precondition(blueprint, _make_message(TRAINEE, false)),
		MoveCommand.PreconditionFailureCause.NOT_ENOUGH_ENERGY,
		"refused even though the unit itself is affordable — the structure isn't paid for"
	)


func test_training_at_an_unfunded_blueprint_is_queued_with_the_modifier() -> void:
	var commander := _make_commander(1000)
	var blueprint := _make_producer([TRAINEE], commander)
	blueprint.set_awaiting_funds(true)
	assert_eq(
		Train.meets_precondition(blueprint, _make_message(TRAINEE, true)),
		MoveCommand.PreconditionFailureCause.NONE,
		"with the modifier held it is accepted and waits for the structure"
	)


## The deliberate feature this must not break: a blueprint whose build IS funded is still
## orderable, mode or no mode. Queuing units at a building the builder is walking to costs
## nothing but time.
func test_training_at_a_funded_blueprint_is_allowed_either_way() -> void:
	var commander := _make_commander(1000)
	var blueprint := _make_producer([TRAINEE], commander)
	blueprint.set_awaiting_funds(false)
	assert_eq(
		Train.meets_precondition(blueprint, _make_message(TRAINEE, false)),
		MoveCommand.PreconditionFailureCause.NONE,
		"a funded blueprint still takes orders with no modifier held"
	)
