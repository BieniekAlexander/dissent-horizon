extends GutTest

## THE SHARED SAVINGS GOAL (BotSavings): the most valuable proposal is the goal, and anything
## else may spend only what leaves its price banked. Without it every producer bought what it
## could afford the moment it could, and nothing dear was ever bought.

var _savings: BotSavings


func before_each() -> void:
	_savings = BotSavings.new()


func test_the_most_valuable_proposal_is_the_goal() -> void:
	_savings.propose(&"production", &"cheap", 0.4, 100)
	_savings.propose(&"economy", &"factory", 0.6, 1200)
	assert_eq(_savings.goal(), &"factory")


func test_anything_else_must_leave_the_goal_banked() -> void:
	_savings.propose(&"economy", &"factory", 0.6, 1200)
	assert_eq(_savings.claim_against(&"recruit"), 1200)
	assert_eq(_savings.claim_against(&"factory"), 0, "the goal itself spends freely")


func test_a_new_proposal_from_the_same_source_replaces_its_last() -> void:
	_savings.propose(&"economy", &"factory", 0.6, 1200)
	_savings.propose(&"economy", &"lab", 0.5, 800)
	assert_eq(_savings.goal(), &"lab")
	_savings.propose(&"economy", &"", 0.0, 0)
	assert_eq(_savings.goal(), &"", "withdrawn")


func test_buying_the_goal_ends_it() -> void:
	_savings.propose(&"economy", &"factory", 0.6, 1200)
	_savings.propose(&"production", &"cheap", 0.4, 100)
	_savings.spent(&"factory")
	assert_eq(_savings.goal(), &"cheap", "the next best is saved for")


func test_the_claim_lifts_while_the_base_is_threatened() -> void:
	_savings.propose(&"economy", &"factory", 0.6, 1200)
	_savings.held = false
	assert_eq(_savings.claim_against(&"recruit"), 0, "defenders are trained whatever is saved for")


func test_a_tie_goes_to_the_dearer_purchase() -> void:
	_savings.propose(&"production", &"cheap", 0.5, 100)
	_savings.propose(&"economy", &"factory", 0.5, 1200)
	assert_eq(_savings.goal(), &"factory")


func test_every_proposal_is_readable_and_a_copy() -> void:
	_savings.propose(&"economy", &"factory", 0.6, 1200)
	var proposals: Dictionary = _savings.proposals()
	assert_eq(proposals[&"economy"]["type"], &"factory")
	proposals[&"economy"]["cost"] = 1
	assert_eq(_savings.proposals()[&"economy"]["cost"], 1200)


func test_a_demanded_proposal_outranks_a_valued_one_only_at_equal_value() -> void:
	_savings.propose(&"economy", &"factory", 0.6, 1200)
	_savings.propose(&"siege", &"gun_tech", 0.6, 800, true)
	assert_eq(_savings.goal(), &"gun_tech", "equal value: the demand, not the dearer")
	_savings.propose(&"economy", &"factory", 0.7, 1200)
	assert_eq(_savings.goal(), &"factory", "a higher value still wins outright")
