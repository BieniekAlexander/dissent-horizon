extends GutTest

## The three economy figures on Commander: energy committed in the queue, collection rate from
## structures, and spend rate from what is actively being trained.
##
## They exist to PARTITION the economy — committed energy covers the queue side, spend rate
## covers the in-progress side, and neither double-counts the other — so most of what is
## pinned here is the boundary between them: a purchase moving from queued to training must
## leave one figure and enter the other.
##
## Built out of tree, like test_ProductionQueue: a Commander that was never added to the
## scene, plus bare Commandables carrying the components each figure reads.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_EconomyReadouts.gd -gexit

const IRREGULAR: StringName = &"fake_unit"

## Both generators bank on the same period, so a rate of N per tick-period is N/5 per second.
const PERIOD_SECONDS: float = 5.0


## Any piece whose scene provides infrastructure — a harness for the faction-source rule, not a
## figure under test.
const PROVIDER_ID: StringName = &"fake_provider"


func after_each() -> void:
	FakePieces.restore_tools()


func _make_commander(a_energy: int = 0) -> Commander:
	var commander := autofree(Commander.new()) as Commander
	commander.energy = a_energy
	return commander


func _make_producer(a_commander: Commander, a_types: Array[StringName]) -> Commandable:
	var producer := autofree(Commandable.new()) as Commandable
	var production := Production.new()
	production.producible_types = a_types
	producer.add_child(production)
	producer.production = production
	a_commander.add_child(producer)
	return producer


func _make_tool(a_type: StringName) -> Tool:
	return Tool.new("command_tool_%s" % a_type, a_type, null, str(a_type), Vector2i.ZERO, 0, 0)


func _train_purchase(
	a_commander: Commander, a_type: StringName, a_energy: int, a_producers: Array, a_ticks: int = 10
) -> PurchaseTransaction:
	var transaction := PurchaseTransaction.for_cost(
		a_commander, PurchaseTransaction.Kind.TRAIN, _make_tool(a_type), a_energy
	)
	transaction.creation_time = a_ticks
	transaction.dispatch_filter.assign(a_producers)
	return transaction


# --- Committed energy ------------------------------------------------------------

func test_nothing_queued_commits_nothing() -> void:
	assert_eq(_make_commander(500).energy_committed(), 0)


func test_queued_purchases_are_counted_as_committed() -> void:
	var commander := _make_commander(0)
	var producer := _make_producer(commander, [IRREGULAR])
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 40, [producer]))
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 40, [producer]))
	assert_eq(commander.energy_committed(), 80, "both waiting purchases are promised energy")


func test_a_dispatched_purchase_stops_being_committed() -> void:
	# The boundary between the two figures: once a producer has started on it, the purchase
	# has been PAID, so counting it as committed as well would double-count it.
	var commander := _make_commander(40)
	var producer := _make_producer(commander, [IRREGULAR])
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 40, [producer]))
	assert_eq(commander.energy, 0, "the cost came out of the pool")
	assert_eq(commander.energy_committed(), 0, "and is no longer a promise")


func test_cancelling_releases_the_commitment() -> void:
	var commander := _make_commander(0)
	var producer := _make_producer(commander, [IRREGULAR])
	var transaction := commander.production_queue.submit(
		_train_purchase(commander, IRREGULAR, 40, [producer])
	)
	commander.production_queue.cancel(transaction)
	assert_eq(commander.energy_committed(), 0)


func test_dominion_purchases_commit_dominion_not_energy() -> void:
	# A purchase costs energy OR dominion, never both, so the two sums are disjoint.
	var commander := _make_commander(0)
	var producer := _make_producer(commander, [IRREGULAR])
	var transaction := PurchaseTransaction.for_cost(
		commander, PurchaseTransaction.Kind.TRAIN, _make_tool(IRREGULAR), 0, 30
	)
	transaction.dispatch_filter.assign([producer])
	commander.production_queue.submit(transaction)
	assert_eq(commander.energy_committed(), 0)
	assert_eq(commander.dominion_committed(), 30)


# --- Collection rate ----------------------------------------------------------

func test_no_extractors_collect_nothing() -> void:
	assert_almost_eq(_make_commander().energy_collection_rate(), 0.0, 0.001)


func test_extractors_sum_into_a_per_second_rate() -> void:
	var commander := _make_commander()
	for rate: int in [25, 10]:
		var extractor := autofree(Commandable.new()) as Commandable
		var energy_extractor := EnergyExtractor.new()
		energy_extractor.name = "EnergyExtractor"
		energy_extractor.energy_rate = rate
		extractor.add_child(energy_extractor)
		commander.add_child(extractor)
	assert_almost_eq(commander.energy_collection_rate(), 35.0 / PERIOD_SECONDS, 0.001)


func test_a_blueprint_collects_nothing() -> void:
	# A plan neither collects nor spends — counting one would report income from an extractor
	# that has not been built.
	var commander := _make_commander()
	var extractor := autofree(Commandable.new()) as Commandable
	var energy_extractor := EnergyExtractor.new()
	energy_extractor.name = "EnergyExtractor"
	extractor.add_child(energy_extractor)
	extractor.is_planned = true
	commander.add_child(extractor)
	assert_almost_eq(commander.energy_collection_rate(), 0.0, 0.001)


func test_a_blueprint_extractor_is_pending_income() -> void:
	# ...but it is income ORDERED, which the energy bar draws as pending.
	var commander := _make_commander()
	var extractor := autofree(Commandable.new()) as Commandable
	var energy_extractor := EnergyExtractor.new()
	energy_extractor.name = "EnergyExtractor"
	energy_extractor.energy_rate = 25
	extractor.add_child(energy_extractor)
	extractor.is_planned = true
	commander.add_child(extractor)
	assert_almost_eq(commander.pending_energy_collection_rate(), 25.0 / PERIOD_SECONDS, 0.001)


# --- Spend rate ---------------------------------------------------------------

func test_an_idle_producer_spends_nothing() -> void:
	var commander := _make_commander()
	_make_producer(commander, [IRREGULAR])
	assert_almost_eq(commander.energy_spend_rate(), 0.0, 0.001)


func test_spend_rate_spreads_an_active_job_over_its_build_time() -> void:
	var commander := _make_commander()
	commander.technology_mapping[IRREGULAR] = TechnologySpec.new(60, 0, 0, 30)
	var producer := _make_producer(commander, [IRREGULAR])
	# 60 energy over 30 ticks, at 30 physics ticks per second, is 60 energy per second.
	producer.production.enqueue(30, null, IRREGULAR)
	assert_almost_eq(
		commander.energy_spend_rate(),
		60.0 * Engine.physics_ticks_per_second / 30.0,
		0.001
	)


func test_a_queued_purchase_is_not_yet_a_spend() -> void:
	# The other side of the partition: what is queued is committed, not spent. A spend rate
	# that included the queue would overlap with committed energy and mislead in both
	# directions.
	var commander := _make_commander(0)
	commander.technology_mapping[IRREGULAR] = TechnologySpec.new(60, 0, 0, 30)
	var producer := _make_producer(commander, [IRREGULAR])
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 60, [producer], 30))
	assert_eq(commander.energy_committed(), 60, "it is committed")
	assert_almost_eq(commander.energy_spend_rate(), 0.0, 0.001, "but nothing is being built yet")


# --- Attribution counts -------------------------------------------------------
##
## A rate that explains itself ("+14/s · 4 extractors") is worth far more than a bare one, and
## the counts have to describe the SAME set of structures the rate sums over or the two
## readings contradict each other.

func _make_extractor(a_commander: Commander, a_rate: int = 25) -> Commandable:
	var extractor := autofree(Commandable.new()) as Commandable
	var energy_extractor := EnergyExtractor.new()
	energy_extractor.name = "EnergyExtractor"
	energy_extractor.energy_rate = a_rate
	extractor.add_child(energy_extractor)
	a_commander.add_child(extractor)
	return extractor


func _make_dominion_source(a_commander: Commander, a_rate: int = 10) -> Commandable:
	var source := autofree(Commandable.new()) as Commandable
	var generator := DominionGenerator.new()
	generator.name = "DominionGenerator"
	generator.dominion_rate = a_rate
	source.add_child(generator)
	a_commander.add_child(source)
	return source


func test_extractor_count_matches_the_structures_the_energy_rate_sums_over() -> void:
	var commander := _make_commander()
	_make_extractor(commander)
	_make_extractor(commander)
	assert_eq(commander.energy_source_count(), 2)


func test_a_blueprint_extractor_is_not_counted() -> void:
	# Same exclusion the rate applies: a planned extractor collects nothing, so counting it would
	# make the attribution disagree with the figure it explains.
	var commander := _make_commander()
	_make_extractor(commander).is_planned = true
	assert_eq(commander.energy_source_count(), 0)
	assert_almost_eq(commander.energy_collection_rate(), 0.0, 0.001)


func test_a_flat_dominion_generator_reports_a_source_but_no_contributors() -> void:
	# The base generator awards a flat rate with nothing feeding it, so there is a rate to
	# show and nothing to attribute it to.
	var commander := _make_commander()
	_make_dominion_source(commander)
	assert_eq(commander.dominion_source_count(), 1)
	assert_eq(commander.dominion_contributor_count(), DominionGenerator.NO_ATTRIBUTION)


func test_a_commander_with_no_generators_reports_no_dominion_source() -> void:
	# This is what handles a faction whose dominion is EVENT-driven — awarded for damage
	# dealt rather than per tick. It owns no generator, so it reports no source, and the
	# readout omits the rate line rather than printing a "+0/s" that asserts something false.
	var commander := _make_commander()
	_make_extractor(commander)
	assert_eq(commander.dominion_source_count(), 0)


# --- The Compound's rate follows LIVE occupancy, not the inherited flat default -----
##
## OccupantDominionGenerator (the Compound) inherits `dominion_rate` from the base
## DominionGenerator but never pays it out — its real payout is `dominion_per_unit *
## contributor_count()`, computed fresh each cycle. dominion_collection_rate() used to read
## the bare `dominion_rate` field directly, which reported a rate that never moved with how
## many prisoners were actually held — effectively always the class's unused script default.

func _make_occupant_dominion_source(
	a_commander: Commander, a_dominion_per_unit: int, a_occupant_count: int
) -> Commandable:
	var host := autofree(Commandable.new()) as Commandable
	var garrison := Garrison.new()
	garrison.name = "Garrison"
	host.add_child(garrison)
	var generator := OccupantDominionGenerator.new()
	generator.name = "DominionGenerator"
	generator.dominion_per_unit = a_dominion_per_unit
	host.add_child(generator)
	a_commander.add_child(host)
	for i: int in a_occupant_count:
		garrison._garrisoned.append(autofree(Commandable.new()) as Commandable)
	return host


func test_the_rate_scales_with_how_many_are_actually_held() -> void:
	var commander := _make_commander()
	_make_occupant_dominion_source(commander, 5, 3)
	var expected: float = 5.0 * 3.0 / PERIOD_SECONDS
	assert_almost_eq(commander.dominion_collection_rate(), expected, 0.01)


func test_an_empty_compound_reports_no_rate() -> void:
	var commander := _make_commander()
	_make_occupant_dominion_source(commander, 5, 0)
	assert_almost_eq(commander.dominion_collection_rate(), 0.0, 0.001)


func test_the_rate_does_not_read_the_unused_inherited_flat_default() -> void:
	var commander := _make_commander()
	var host := _make_occupant_dominion_source(commander, 5, 3)
	var generator := host.get_node("DominionGenerator") as OccupantDominionGenerator
	assert_eq(generator.dominion_rate, 10, "the inherited default — present, but never paid out")
	var rate_if_it_had_used_the_flat_default: float = 10.0 / PERIOD_SECONDS
	assert_ne(commander.dominion_collection_rate(), rate_if_it_had_used_the_flat_default,
		"the bug this guards: representing the Compound as if the flat default applied")


func test_occupant_generators_contribute_their_head_count() -> void:
	var commander := _make_commander()
	for held: int in [3, 1]:
		var camp := autofree(Commandable.new()) as Commandable
		# Ownership is wired to the field directly, like `production` elsewhere in this file:
		# the @onready never resolves for a node built out of tree, and Garrison reads the
		# host's commander_id when it takes an occupant.
		var camp_ownership := Ownership.new()
		camp_ownership.name = "Ownership"
		camp.add_child(camp_ownership)
		camp.ownership = camp_ownership
		camp.ownership.commander = commander
		var generator := OccupantDominionGenerator.new()
		generator.name = "DominionGenerator"
		var garrison := Garrison.new()
		garrison.name = "Garrison"
		garrison.capacity = 10
		# Occupants are held as ORPHANED nodes, so the garrison is filled by handing it
		# entities rather than by parenting them.
		camp.add_child(garrison)
		camp.add_child(generator)
		commander.add_child(camp)
		for i in held:
			var prisoner := autofree(Commandable.new()) as Commandable
			garrison.garrison(prisoner)
	assert_eq(commander.dominion_contributor_count(), 4,
		"prisoners across every camp, since that is what the Colonial rate is made of")


# --- Clearance time -----------------------------------------------------------

func test_nothing_owed_clears_immediately() -> void:
	var commander := _make_commander(500)
	assert_almost_eq(commander.energy_clearance_seconds(), 0.0, 0.001)


func test_clearance_divides_the_shortfall_by_net_income() -> void:
	var commander := _make_commander(0)
	var producer := _make_producer(commander, [IRREGULAR])
	# 100 energy owed, nothing banked, and one extractor banking 25 per 5s = 5/s. Nothing is
	# training, so net income is the whole collection rate.
	_make_extractor(commander, 25)
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 100, [producer]))
	assert_eq(commander.energy_committed(), 100, "queued and unpaid")
	assert_almost_eq(commander.energy_clearance_seconds(), 20.0, 0.001)


func test_no_net_income_never_clears() -> void:
	# Reported as "not clearing" rather than as an enormous number the player has to read
	# and interpret: a commitment that is not being paid down at all is the state worth
	# flagging.
	var commander := _make_commander(0)
	var producer := _make_producer(commander, [IRREGULAR])
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 100, [producer]))
	assert_eq(commander.energy_clearance_seconds(), -1.0)


# --- Infrastructure provider grant ---------------------------------------------
##
## InfrastructureBar's segment size (gdd/systems/ux/ui/economy-bars.md §Infrastructure): the
## capacity ONE owned provider grants, read off what the commander actually built rather than
## assumed from a faction constant.

func _make_infrastructure_provider(a_commander: Commander, a_grant: int) -> Commandable:
	var provider := autofree(Commandable.new()) as Commandable
	provider.infrastructure = a_grant
	a_commander.add_child(provider)
	return provider


func test_a_faction_naming_no_provider_draws_no_segments() -> void:
	var commander := _make_commander()
	commander.faction = autofree(Faction.new()) as Faction
	assert_eq(commander.infrastructure_provider_grant(), 0)


## The segment size is the faction's DEDICATED provider's grant — read off its piece whether or
## not one stands, and unmoved by other providers (a command centre grants a different amount).
func test_the_grant_is_the_dedicated_providers_whether_or_not_one_stands() -> void:
	var commander := _make_commander()
	var faction := autofree(Faction.new()) as Faction
	faction.infrastructure_source = PROVIDER_ID
	commander.faction = faction
	FakePieces.register_tool(FakePieces.tool(PROVIDER_ID, {"structure": true, "infrastructure": 40}))
	var own_grant: int = (commander.get_build_preview_instance(Tool.for_type(PROVIDER_ID))
		as Commandable).infrastructure
	assert_gt(own_grant, 0, "guards the fixture: the source provides")
	assert_eq(commander.infrastructure_provider_grant(), own_grant, "none standing yet")
	_make_infrastructure_provider(commander, own_grant * 3)
	assert_eq(commander.infrastructure_provider_grant(), own_grant,
		"a different provider standing does not resize the segment")


# --- Pending pieces --------------------------------------------------------------

func test_a_blueprint_is_pending_capacity_not_real_capacity() -> void:
	var commander := _make_commander()
	var before: int = commander.infrastructure_provided
	_make_infrastructure_provider(commander, 500).is_planned = true
	assert_eq(commander.infrastructure_provided, before, "a plan provides nothing yet")
	assert_eq(commander.pending_infrastructure_provided(), 500)


func test_a_structure_going_up_is_pending_upkeep() -> void:
	var commander := _make_commander()
	var consumer := _make_infrastructure_provider(commander, -80)
	consumer.add_to_group("structure")
	consumer.build_progress = 0.5
	assert_eq(commander.pending_infrastructure_required(), 80)
	assert_eq(commander.pending_infrastructure_provided(), 0)


func test_a_standing_piece_is_not_pending() -> void:
	var commander := _make_commander()
	_make_infrastructure_provider(commander, 500)
	assert_eq(commander.pending_infrastructure_provided(), 0)


func test_a_standing_template_commits_nothing() -> void:
	# A standing entry soaks idle income; it is a policy, and each copy it issues is the order.
	var commander := _make_commander(0)
	var producer := _make_producer(commander, [IRREGULAR])
	var template := _train_purchase(commander, IRREGULAR, 40, [producer])
	template.standing = true
	commander.production_queue.submit(template)
	assert_eq(commander.energy_committed(), 0)


