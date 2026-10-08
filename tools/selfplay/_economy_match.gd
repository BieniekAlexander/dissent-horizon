extends "res://tools/selfplay/run_match.gd"

## TEMPORARY economy probe (delete me). Adds an ENERGY LEDGER to every sample, so the
## question "how can a bot with a reserve threshold be broke?" can be answered with
## measurement rather than with reasoning.
##
## Reads only. Per physics tick, per commander, it records:
##   * the balance, and how often it is exactly zero / at-or-above the reserve;
##   * committed-but-unpaid energy (the queue side), so "broke" can be distinguished from
##     "the balance is zero because the queue holds the state";
##   * every debit, attributed to the path that made it — TRAIN (BotProduction) or BUILD
##     (BotEconomy) — by watching the producer's training_queue and the commander's
##     production queue rather than by instrumenting the spend itself;
##   * income, integrated from Commander.energy_collection_rate().

var _ledger: Dictionary = {}  # commander id -> Dictionary
var _seen_build_ids: Dictionary = {}  # commander id -> { transaction id: true }
var _seen_train_ids: Dictionary = {}  # commander id -> { transaction id: true }


func _fresh_ledger() -> Dictionary:
	return {
		"ticks": 0,
		"ticks_zero_energy": 0,
		"ticks_at_reserve": 0,
		"peak_energy": 0,
		"income_total": 0.0,
		"train_debits": 0,
		"train_energy": 0,
		"build_debits": 0,
		"build_energy": 0,
		"ticks_queue_nonempty": 0,
		"ticks_committed_nonzero": 0,
		"peak_committed": 0,
		"peak_production_structures": 0,
		"peak_extractors": 0,
	}


func _physics_process(a_delta: float) -> void:
	if _scenario == null:
		return
	for slot: PlayerSlot in _scenario.player_slots:
		var commander: Commander = slot.commander
		if commander == null:
			continue
		_observe(commander, a_delta)


func _observe(a_commander: Commander, a_delta: float) -> void:
	var key: int = a_commander.id
	if not _ledger.has(key):
		_ledger[key] = _fresh_ledger()
		_seen_build_ids[key] = {}
		_seen_train_ids[key] = {}
	var led: Dictionary = _ledger[key]
	var reserve: int = _reserve_for(a_commander)

	led["ticks"] += 1
	if a_commander.energy == 0:
		led["ticks_zero_energy"] += 1
	if a_commander.energy >= reserve:
		led["ticks_at_reserve"] += 1
	led["peak_energy"] = maxi(led["peak_energy"], a_commander.energy)
	led["income_total"] += a_commander.energy_collection_rate() * a_delta

	var committed: int = a_commander.energy_committed()
	led["peak_committed"] = maxi(led["peak_committed"], committed)
	if committed > 0:
		led["ticks_committed_nonzero"] += 1
	if not a_commander.production_queue.is_empty():
		led["ticks_queue_nonempty"] += 1

	# BUILD debits: a BUILD transaction sits in the queue (FUNDED) while its builder walks,
	# so it is observable from the queue. Counted once, the first tick it is seen.
	var builds: Dictionary = _seen_build_ids[key]
	for transaction: PurchaseTransaction in a_commander.production_queue.entries:
		if transaction.kind != PurchaseTransaction.Kind.BUILD:
			continue
		if builds.has(transaction.id):
			continue
		builds[transaction.id] = true
		led["build_debits"] += 1
		led["build_energy"] += transaction.energy_cost

	# TRAIN debits: an affordable train is submitted, funded, dispatched and REMOVED from the
	# queue inside one submit() call, so it is never visible there on a later frame. It is
	# visible at the producer, which is where the job lands.
	var trains: Dictionary = _seen_train_ids[key]
	var production_structures: int = 0
	var extractors: int = 0
	for child: Node in a_commander.get_children():
		var entity := child as Actor
		if entity == null or entity.is_queued_for_deletion():
			continue
		if entity.has_node("Fixture"):
			if entity.production != null:
				production_structures += 1
			if entity.has_node("EnergyExtractor") and entity.is_built:
				extractors += 1
		if entity.production == null:
			continue
		for i: int in entity.production.training_queue.size():
			var transaction: PurchaseTransaction = entity.production.job_transaction(i)
			if transaction == null or trains.has(transaction.id):
				continue
			trains[transaction.id] = true
			led["train_debits"] += 1
			led["train_energy"] += transaction.energy_cost
	led["peak_production_structures"] = maxi(
		led["peak_production_structures"], production_structures
	)
	led["peak_extractors"] = maxi(led["peak_extractors"], extractors)


## The economy reserve this commander is playing by, or 0 when it has no brain yet.
func _reserve_for(a_commander: Commander) -> int:
	var brain: BotBrain = a_commander.get_node_or_null("BotBrain") as BotBrain
	if brain == null or brain.config == null:
		return 0
	return brain.config.economy_reserve


func _slot_sample(a_commander: Commander) -> Dictionary:
	var base: Dictionary = super._slot_sample(a_commander)
	if a_commander == null:
		return base
	base["energy_committed"] = a_commander.energy_committed()
	base["queue_len"] = a_commander.production_queue.entries.size()
	base["collection_rate"] = a_commander.energy_collection_rate()
	base["spend_rate"] = a_commander.energy_spend_rate()
	base["infrastructure"] = a_commander.infrastructure
	var reserve: int = _reserve_for(a_commander)
	base["reserve"] = reserve
	base["at_reserve"] = a_commander.energy >= reserve
	var production_structures: int = 0
	for child: Node in a_commander.get_children():
		var entity := child as Actor
		if (
			entity != null
			and not entity.is_queued_for_deletion()
			and entity.has_node("Fixture")
			and entity.production != null
		):
			production_structures += 1
	base["production_structures"] = production_structures
	base["ledger"] = _ledger.get(a_commander.id, {})
	base["diag"] = _diag(a_commander)
	return base


## What BotEconomy sees at this instant: the buildable sets it derives, which of them it can
## afford, whether a builder and an unclaimed site exist, and which branch of tick() the
## state selects. This is the reserve check's inputs and outcome, read from outside.
func _diag(a_commander: Commander) -> Dictionary:
	var brain: BotBrain = a_commander.get_node_or_null("BotBrain") as BotBrain
	if brain == null or brain._economy == null:
		return {}
	var economy: BotEconomy = brain._economy
	var bot: Bot = brain.bot
	var builders: int = 0
	for u: Actor in bot.get_units():
		if u.has_node("Builds"):
			builders += 1
	var income_types: Array = bot.buildable_income_structure_types()
	return {
		"buildable": bot.buildable_structure_types(),
		"production_types": bot.buildable_production_structure_types(),
		"income_types": income_types,
		"income_affordable": income_types.filter(func(t): return bot.can_afford(t)),
		"income_cost": income_types.map(func(t): return economy._energy_cost(t)),
		"dominion_types": bot.buildable_dominion_structure_types(),
		"infra_types": bot.buildable_infrastructure_structure_types(),
		"needs_infra": bot.needs_infrastructure_provider(),
		"builders": builders,
		"construction_jobs": economy._construction_job_count(),
		"picked_builder": economy._pick_builder() != null,
		"unclaimed_site": economy._nearest_unclaimed_site() != null,
		"surplus": economy._has_resource_surplus(),
		"prev_energy": economy._prev_energy,
	}
