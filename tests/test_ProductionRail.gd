extends GutTest

## The production rail's run collapsing — the rule that keeps a loaded queue from becoming a
## column of identical squares down the left edge.
##
## Only the pure part is covered here. The rail itself is a Control that reads a live
## ProductionQueue and rebuilds cards, so its layout needs a HUD rig; `_collapse_runs` is
## static and is where the actual rule lives.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ProductionRail.gd -gexit

const IRREGULAR: StringName = &"fake_trainee_a"
const VANGUARD: StringName = &"fake_trainee_b"


func _purchase(a_type: StringName) -> PurchaseTransaction:
	var tool := Tool.new("command_tool_%s" % a_type, a_type, null, str(a_type), Vector2i.ZERO, 0, 0)
	return PurchaseTransaction.for_cost(null, PurchaseTransaction.Kind.TRAIN, tool, 10)


func _runs_of(a_types: Array) -> Array:
	var transactions: Array = []
	for type: StringName in a_types:
		transactions.append(_purchase(type))
	var shapes: Array = []
	for run: Array in ProductionRail._collapse_runs(transactions):
		shapes.append([(run.front() as PurchaseTransaction).type, run.size()])
	return shapes


func test_an_empty_queue_collapses_to_nothing() -> void:
	assert_eq(ProductionRail._collapse_runs([]), [])


func test_identical_adjacent_purchases_become_one_run() -> void:
	assert_eq(_runs_of([IRREGULAR, IRREGULAR, IRREGULAR]), [[IRREGULAR, 3]])


func test_a_separated_pair_stays_two_runs() -> void:
	# Adjacency is the whole constraint. Folding the two Irregular runs together would claim
	# a dispatch order the queue does not have — the Vanguard really is built between them.
	assert_eq(
		_runs_of([IRREGULAR, VANGUARD, IRREGULAR]),
		[[IRREGULAR, 1], [VANGUARD, 1], [IRREGULAR, 1]]
	)


func test_runs_keep_queue_order() -> void:
	assert_eq(
		_runs_of([VANGUARD, VANGUARD, IRREGULAR]),
		[[VANGUARD, 2], [IRREGULAR, 1]]
	)


func test_every_purchase_survives_the_collapse() -> void:
	# A collapsed chip cancels one of the purchases it stands for, so none may be dropped.
	var transactions: Array = []
	for type: StringName in [IRREGULAR, IRREGULAR, VANGUARD, IRREGULAR]:
		transactions.append(_purchase(type))
	var total: int = 0
	for run: Array in ProductionRail._collapse_runs(transactions):
		total += run.size()
	assert_eq(total, transactions.size())
