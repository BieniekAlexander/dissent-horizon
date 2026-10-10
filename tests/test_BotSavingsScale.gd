extends GutTest

## EVERY SAVINGS PROPOSAL IS ON THE ONE PURCHASE SCALE. Production's proposal used to be the
## demand map's unit_composition_value (values near 1–7) while the economy's was the learned
## model's marginal per energy (near 0.001), so production's unit won the goal every think and
## no tech structure was ever banked for — found 2026-10-10 when the Constable cleared the tech
## rung's margin in a ten-minute game and the bank still never held its price
## (gdd/systems/ai/bot-architecture.md §The tech rung).

const RECRUIT: StringName = &"test_recruit"
const CONSTABLE: StringName = &"test_constable"


## Answers both valuations, on their two scales, so the test can tell which one a proposal read.
class FakeBot:
	extends Bot
	var per_energy: Dictionary = {RECRUIT: 0.0009, CONSTABLE: 0.0012}

	func purchase_values_per_energy(a_types: Array, _a_demand: Dictionary = {}) -> Dictionary:
		var values: Dictionary = {}
		for t: StringName in a_types:
			values[t] = per_energy[t]
		return {"values": values, "learned": true}

	func unit_composition_value(_a_unit_type, _a_demand: Dictionary) -> float:
		return 5.0  # the demand map's scale: anything here outranks every per-energy value


var _bot: FakeBot


func before_each() -> void:
	_bot = FakeBot.new()
	_bot.technology_mapping = {
		RECRUIT: TechnologySpec.new(100, 0, 0, 30),
		CONSTABLE: TechnologySpec.new(400, 0, 0, 30),
	}


func after_each() -> void:
	_bot.free()


func test_productions_proposal_is_on_the_purchase_scale() -> void:
	var production := BotProduction.new(_bot, BotActuator.new(null))
	var producer := autofree(Actor.new()) as Actor
	production._propose_savings([[producer, RECRUIT]], {&"enemy": {"demand": 1.0, "rep": null}})
	var proposal: Dictionary = _bot.savings.proposals()[&"production"]
	assert_eq(proposal["type"], RECRUIT)
	assert_almost_eq(float(proposal["value"]), 0.0009, 1e-9, "per energy, not the demand map's 5.0")
	assert_eq(proposal["cost"], 100)


func test_a_tech_proposal_on_the_same_scale_can_win_the_goal() -> void:
	# What the fix is for: with both on one scale, the dearer, better-valued tech purchase
	# becomes the goal and the bank is held for it.
	var production := BotProduction.new(_bot, BotActuator.new(null))
	var producer := autofree(Actor.new()) as Actor
	production._propose_savings([[producer, RECRUIT]], {&"enemy": {"demand": 1.0, "rep": null}})
	_bot.savings.propose(&"economy", &"test_tech", 0.0012, 1200)
	assert_eq(_bot.savings.goal(), &"test_tech")
	assert_eq(_bot.savings.claim_against(RECRUIT), 1200, "recruits leave the tech's price banked")


func test_nothing_wanted_withdraws_the_proposal() -> void:
	var production := BotProduction.new(_bot, BotActuator.new(null))
	var producer := autofree(Actor.new()) as Actor
	production._propose_savings([[producer, RECRUIT]], {})
	production._propose_savings([[producer, &""]], {})
	assert_false(_bot.savings.proposals().has(&"production"))
