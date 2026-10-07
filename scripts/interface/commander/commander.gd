@tool
class_name Commander
extends Node

#region Properties

#region Identifiers
const NUM_MAX_COMMANDERS: int = 8
@export_range(0, NUM_MAX_COMMANDERS + 1) var id: int


## Whether `a_commander_id` is on this commander's side — whose pending pieces this one's HUD
## shows, and whose planned sites it may not build over.
## PLANNED — ALLIES: a side is the commander alone until alliances land
## (gdd/systems/combat/target-acquisition.md §Alliances); then an ally answers true too.
func shares_side_with(a_commander_id: int) -> bool:
	return a_commander_id == id


#endregion

#region Faction
## Scene defining this commander's Faction (e.g. anarchical.tscn). Instanced at
## ready into `faction`, which is the single source of truth for what this
## commander can deploy — its starting units and available Sanctions.
##
## Deliberately NOT an @export: a commander's faction is SCENARIO configuration
## (PlayerSlot.faction), and Scenario._build_commanders assigns it before the
## commander enters the tree. Exporting it let a rig scene carry its own default —
## player.tscn shipped one — which silently won whenever a slot named no faction,
## so the scenario appeared to configure something it did not actually control.
## Scenario now requires every slot to name a faction, leaving exactly one place
## the answer can come from.
var faction_scene: PackedScene

## The live Faction instance for this commander (child of this node). Null until
## ready. Also null for the neutral world commander (id 0), which is not a player
## slot and fields nothing.
var faction: Faction = null

## This commander's per-match sanction state, built from the faction's sanction grid:
## which sanctions are unlocked (dominion-gated) and their live cooldowns. Null when
## the commander has no faction.
var sanction_grid: SanctionGrid = null

## The drops this commander still holds while its scenario deploys by drop — see Deployment.
## Null means this commander's scenario places its base some other way (authored, or none).
var deployment: Deployment = null


## This commander's dominion route, or null when its faction has none. Memoized per faction
## instance, because the HUD asks every frame and the search walks a subtree; a faction's route
## never changes once instanced. Unmemoized before the faction exists (test harnesses).
func dominion_route() -> DominionRoute:
	if faction == null:
		return DominionRoute.for_commander(self)
	if _dominion_route_faction_id != faction.get_instance_id():
		_dominion_route_faction_id = faction.get_instance_id()
		_dominion_route = DominionRoute.for_commander(self)
	return _dominion_route if is_instance_valid(_dominion_route) else null


var _dominion_route: DominionRoute = null
var _dominion_route_faction_id: int = 0
#endregion

#region Controls
@onready var selection: Array[Commandable] = []
@onready var click_screen_pos: Vector2 = Vector2.ZERO
#endregion

#region Perception
## References resolved from the scene tree at _ready (Scenario/Players/<commander>),
## required by the fog-limited perception queries below and by the blackboard.
## May be injected explicitly via initialize() instead.
var map: Map
var scenario: Scenario

## Persistent, fog-limited belief about the enemy PLUS the visual memory of scouted
## structures (see CommanderBlackboard). Created at runtime for every non-neutral
## commander (player and bot alike) and ticked on a throttled cadence below. Null in
## the editor and for the neutral (id 0) commander.
var blackboard: CommanderBlackboard

## The squads being kept to a policy on this commander's behalf — the Bot's military's, or a
## mission tactic's over one of its clusters. Shared action side, separate decision side:
## gdd/systems/ai/squads-and-relations.md §Squads.
var squads: SquadRegistry = SquadRegistry.new()

## Physics ticks between belief updates (~5 Hz). The AI-only belief layer doesn't
## need to run every physics frame, and its visible_enemies() step runs expensive
## physics-space queries. The player-facing snapshot layer is NOT throttled — it
## runs every frame in blackboard.refresh_snapshots() (see _physics_process).
const BLACKBOARD_TICK_INTERVAL: int = 6
var _ticks_since_blackboard: int = 0
#endregion

#region Resources
## Starting energy/dominion are applied per-commander from its PlayerSlot (see
## Scenario); a commander built without a slot (the neutral world commander) keeps
## these zero defaults. NOT @onready — Scenario sets them before the commander enters
## the tree, and an @onready initializer would clobber that at _ready.
var energy: int = 0
var dominion: int = 0

## Infrastructure is the "power" resource. Each commandable carries ONE signed `infrastructure` int
## (positive = provides, negative = consumes — see Commandable); the commander tallies
## those into capacity (infrastructure_provided) and upkeep (infrastructure_required) so
## the HUD can show used/total. Every commander starts with a base 100 capacity; entities add/remove
## their contribution at runtime via add_infrastructure / remove_infrastructure. When upkeep exceeds
## capacity the commander is "strained" — production runs at reduced speed.
const BASE_INFRASTRUCTURE: int = 100
var infrastructure_provided: int = BASE_INFRASTRUCTURE
var infrastructure_required: int = 0
## Spare capacity (capacity minus upkeep); negative when strained.
var infrastructure:
	get:
		return infrastructure_provided - infrastructure_required

## Emitted whenever any resource pool changes. Lets the HUD (and any other
## listener) update on change instead of polling every frame. All resource
## mutation goes through the mutators below so this fires consistently.
signal resources_changed


## Add `amount` energy (negative to spend). Single write-point for the energy pool.
func add_energy(a_amount: int) -> void:
	energy += a_amount
	resources_changed.emit()


## Add `amount` dominion (negative to spend). Single write-point for the dominion pool.
func add_dominion(a_amount: int) -> void:
	dominion += a_amount
	resources_changed.emit()


## The fraction of a killed enemy's energy cost this commander is paid, from the standing
## (passive) sanctions it has unlocked — the Anarchists' Scavenge family. 0.0 when it owns
## none, which is every commander that has not bought into it.
##
## The MAXIMUM rather than the sum: a column is one sanction the player improves, so
## Scavenge 2 replacing Scavenge 1 must pay 20%, not 30%. Supersession already drops the
## parent from `standing_sanctions`, so today the two agree — max is what keeps them
## agreeing if a faction ever authors two unrelated bounty passives, where stacking them
## into a refund larger than the unit's price would print money.
func kill_bounty_rate() -> float:
	if sanction_grid == null:
		return 0.0
	var rate: float = 0.0
	for sanction: Sanction in sanction_grid.standing_sanctions():
		rate = maxf(rate, sanction.kill_bounty_fraction)
	return rate


## Energy owed to this commander for destroying a piece of type `a_type` — its build cost
## scaled by kill_bounty_rate(). 0 when no bounty is owned or the piece is not priced
## (neutral scenery, a scenario-only entity), so an unpriced kill pays nothing rather
## than erroring.
func kill_bounty_for(a_type: StringName) -> int:
	var rate: float = kill_bounty_rate()
	if rate <= 0.0:
		return 0
	var spec: TechnologySpec = technology_mapping.get(a_type)
	if spec == null:
		return 0
	return roundi(spec.energy_cost * rate)


## Credit a commandable's signed infrastructure contribution: a positive `a_infrastructure` raises
## capacity, a negative one raises upkeep, 0 is a no-op.
func add_infrastructure(a_infrastructure: int) -> void:
	_apply_infrastructure(a_infrastructure, 1)


## Withdraw a contribution previously passed to add_infrastructure — on death or when the
## commandable changes hands. Pass the commandable's own (unnegated) infrastructure.
func remove_infrastructure(a_infrastructure: int) -> void:
	_apply_infrastructure(a_infrastructure, -1)


func _apply_infrastructure(a_infrastructure: int, a_sign: int) -> void:
	if a_infrastructure > 0:
		infrastructure_provided += a_infrastructure * a_sign
	elif a_infrastructure < 0:
		infrastructure_required += -a_infrastructure * a_sign
	resources_changed.emit()


## True when upkeep exceeds capacity. Production structures build at reduced speed
## while this holds (see Production.tick).
func is_infrastructure_strained() -> bool:
	return infrastructure_required > infrastructure_provided


## One infrastructure provider's grant — the segment size InfrastructureBar divides by. Read off
## the faction's DEDICATED provider (Faction.infrastructure_source) whether or not one stands
## yet: other pieces provide too (a command centre, often a different amount), and a segment
## that resized as they came and went would stop meaning "one more provider". 0 when the
## faction names none. See gdd/systems/ux/ui/economy-bars.md §Infrastructure.
func infrastructure_provider_grant() -> int:
	if faction == null or faction.infrastructure_source == &"":
		return 0
	# The default variant's: what the faction's provider is when nothing else is asked.
	var source := (
		get_build_preview_instance(Tool.for_type(faction.infrastructure_source)) as Commandable
	)
	return maxi(source.infrastructure, 0) if source != null else 0


#endregion

#region Production queue
## Every purchase this commander makes — training a unit, placing a structure — passes
## through here rather than being rejected for lack of resources. See production_queue.gd.
## Created in _init (not _ready) so it exists for editor instances and for tests that
## never add the commander to a tree.
var production_queue: ProductionQueue


func _init() -> void:
	production_queue = ProductionQueue.new(self)


## Unmet needs the production queue can WAIT OUT: the spendable pools. A purchase
## blocked only by these is queued, not refused. Infrastructure is in the list because it is
## upkeep, not a price — it never prevents a purchase, it only slows production once
## strained. Anything else (a missing prerequisite structure) is a hard refusal at
## order time, since waiting can't resolve it.
static func is_deferrable_need(need: TechnologySpec.UnmetNeed) -> bool:
	return (
		need == TechnologySpec.UnmetNeed.NOT_ENOUGH_ENERGY
		or need == TechnologySpec.UnmetNeed.NOT_ENOUGH_DOMINION
		or need == TechnologySpec.UnmetNeed.NOT_ENOUGH_INFRASTRUCTURE
	)


## The unmet need that should BLOCK an order for `a_type`, or NONE. Tech prerequisites
## always fail here. Resource shortfalls fail here only when `allow_deferral` is false —
## with deferral allowed (the default) the queue waits them out instead.
##
## `allow_deferral` is what the ADDITIVE MODIFIER switches. The player holds the key, the
## controller stamps it on the CommandMessage, and the Train/Build preconditions pass it
## down to here — so an unaffordable purchase is queued when the player has asked for
## that and refused outright when they haven't. It defaults to true so every caller that
## isn't a player order (scenario events, the bot's actuator, tests) keeps the original
## always-defer behavior without having to opt in.
func get_blocking_need(a_type: Variant, a_allow_deferral: bool = true) -> TechnologySpec.UnmetNeed:
	return _blocking_need(a_type, get_unmet_need(a_type), a_allow_deferral)


## get_blocking_need for a Tool, priced by its own form (see get_unmet_need_for).
func get_blocking_need_for(a_tool: Tool, a_allow_deferral: bool = true) -> TechnologySpec.UnmetNeed:
	return _blocking_need(a_tool.type, get_unmet_need_for(a_tool), a_allow_deferral)


func _blocking_need(
	a_type: Variant, a_need: TechnologySpec.UnmetNeed, a_allow_deferral: bool
) -> TechnologySpec.UnmetNeed:
	var need: TechnologySpec.UnmetNeed = a_need
	if not a_allow_deferral:
		return need
	if is_deferrable_need(need):
		return TechnologySpec.UnmetNeed.NONE
	# A missing prerequisite is waitable too — but ONLY when it is already on its way.
	# That is the distinction the whole feature turns on: "I have not built the tech lab"
	# is a refusal, while "the tech lab is going up right now" is a queue. Without it a
	# player could order the whole tech tree from an empty base and watch nothing happen.
	if (
		need == TechnologySpec.UnmetNeed.MISSING_STRUCTURE
		and missing_prerequisites_are_incoming(a_type)
	):
		return TechnologySpec.UnmetNeed.NONE
	return need


## True when EVERY prerequisite `a_type` still lacks is already incoming — planned, under
## construction, or sitting in this commander's production queue as a build purchase.
##
## All, not any: a piece waiting on two buildings is only genuinely on its way once both
## are, and letting it through on one would put a builder at a site it could be stuck at
## indefinitely.
func missing_prerequisites_are_incoming(a_type: Variant) -> bool:
	var spec: TechnologySpec = technology_mapping.get(a_type)
	if spec == null:
		return false
	for required: Variant in spec.required_structures:
		if has_built_structure(required):
			continue
		if not has_incoming_structure(required):
			return false
	return true


## True when a structure of `a_id` is on its way: a BLUEPRINT the player has raised, one
## placed and still going up, or a build purchase still in the queue. All three are asked,
## because a build passes through all three states and no one of them covers the whole trip.
##
## The BLUEPRINT scan is the one that makes prerequisite chains work, and it cannot come
## from `structure_type_map`: a planned structure is deliberately kept out of that registry
## (see Commandable._on_commander_changed — it contributes no infrastructure and is not a building
## the tech tree counts), so it is invisible to the other two checks. Without it a chain of
## A ← B ← C broke at C the moment B's purchase was FUNDED: the transaction leaves the queue
## on funding, and B is then a blueprint nobody has laid a foundation for — on its way by
## every ordinary meaning of the word, and reported as not coming at all.
func has_incoming_structure(a_id: StringName) -> bool:
	for structure: Commandable in _structures_of(a_id).get_values():
		if not structure.is_queued_for_deletion() and not structure.is_built:
			return true
	if production_queue != null and production_queue.has_pending_build(a_id):
		return true
	return has_planned_structure(a_id)


## True when a BLUEPRINT of `a_id` is standing on the map — ordered, sited, and waiting for
## a builder to lay it. Scanned off the owned children rather than a registry, because a
## planned structure is intentionally absent from `structure_type_map`.
func has_planned_structure(a_id: StringName) -> bool:
	return _owned_commandables().any(
		func(c: Commandable) -> bool:
			return c.id == a_id and c.is_planned and not c.is_queued_for_deletion()
	)


## True when `a_type` may be ORDERED — its tech prerequisites are met. Says nothing
## about affordability: an unaffordable purchase is queued, not refused.
func can_order(a_type: Variant) -> bool:
	return get_blocking_need(a_type) == TechnologySpec.UnmetNeed.NONE


#endregion

#endregion

#region Technology
## What a commander can construct: piece id (StringName — see EntityIds) ->
## TechnologySpec, loaded from the GENERATED technology data. The spec importer
## derives that file from each piece's gdd doc (cost / build_time / requires);
## to change costs or prerequisites, edit the doc and re-run the importer.
const TECHNOLOGY_JSON_PATH: String = "res://resources/generated/technology.json"

var technology_mapping: Dictionary = _load_technology()


## PIECE KEYS ONLY. It used to carry int `Ability.Type` values alongside them, as the gate
## for the one hard-coded ability; abilities are doc-governed now and a granted pool is the
## whole permission, so there is nothing for this map to say about them.
static func _load_technology() -> Dictionary:
	var out: Dictionary = {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TECHNOLOGY_JSON_PATH))
	if not (parsed is Dictionary):
		push_error("Commander: cannot load %s — run the spec importer" % TECHNOLOGY_JSON_PATH)
	else:
		for id in parsed:
			var e: Dictionary = parsed[id]
			var requires: Array = []
			for r in e.get("requires", []):
				requires.append(StringName(str(r)))
			out[StringName(str(id))] = TechnologySpec.new(
				int(e["cost"]["energy"]),
				int(e["cost"]["infrastructure"]),
				int(e["cost"]["dominion"]),
				int(e["build_time_ticks"]),
				requires
			)
	return out


#region Upgrades
## Emitted once when an upgrade finishes researching and becomes owned.
signal upgrade_researched(a_id: StringName)

## The upgrades this commander has finished researching, as a set (id -> true). Commander-wide
## and permanent: losing the structure that researched one does not take it back
## (gdd/systems/macroeconomics/upgrades.md).
var _owned_upgrades: Dictionary = {}


func has_upgrade(a_id: StringName) -> bool:
	return _owned_upgrades.has(a_id)


func owned_upgrades() -> Array:
	return _owned_upgrades.keys()


## Mark `a_id` researched. The single write point: Production calls it when a research job
## finishes, and scenario setup or tests may call it directly. Idempotent.
func complete_upgrade(a_id: StringName) -> void:
	if _owned_upgrades.has(a_id):
		return
	_owned_upgrades[a_id] = true
	upgrade_researched.emit(a_id)
	resources_changed.emit()


## True when `a_type` is an upgrade this commander may not buy again: already owned, queued in
## the production queue, or running on one of its producers. An upgrade is bought once, so a
## second order would buy nothing — it is refused (ALREADY_RESEARCHED) rather than queued.
## False for anything that is not an upgrade.
func is_research_taken(a_type: Variant) -> bool:
	if not UpgradeCatalog.is_upgrade(a_type):
		return false
	var id: StringName = StringName(str(a_type))
	if has_upgrade(id):
		return true
	if production_queue != null and production_queue.has_pending_train(id):
		return true
	for commandable: Commandable in _owned_commandables():
		if commandable.production != null and commandable.production.is_producing(id):
			return true
	return false


#endregion


## True iff this commander owns at least one FINISHED (is_built) structure of the
## given piece id. Single source of truth for "is this structure prereq met?",
## shared by proc_technology and ConditionStructureBuilt.
func has_built_structure(a_id: StringName) -> bool:
	return _structures_of(a_id).get_values().any(func(s: Commandable): return s.is_built)


## What stops this commander buying `a_tool`: the piece's prerequisites (read off its `type`) and
## the PRICE of the tool's own form (a variant-bound tool costs what its variant costs).
func get_unmet_need_for(a_tool: Tool) -> TechnologySpec.UnmetNeed:
	var spec: TechnologySpec = technology_mapping.get(a_tool.type)
	if spec == null:
		return TechnologySpec.UnmetNeed.MISSING_STRUCTURE
	if is_research_taken(a_tool.type):
		return TechnologySpec.UnmetNeed.ALREADY_RESEARCHED
	if spec.unmet_need != TechnologySpec.UnmetNeed.NONE:
		return spec.unmet_need
	var priced: TechnologySpec = technology_mapping.get(a_tool.price_id(), spec)
	return priced.get_unmet_need(self)


func get_unmet_need(a_type: Variant) -> TechnologySpec.UnmetNeed:
	var technology_spec: TechnologySpec = technology_mapping.get(a_type)
	if technology_spec == null:
		return TechnologySpec.UnmetNeed.MISSING_STRUCTURE
	if is_research_taken(a_type):
		return TechnologySpec.UnmetNeed.ALREADY_RESEARCHED
	return technology_spec.get_unmet_need(self)


func has_resources_for(a_type: Variant) -> bool:
	return get_unmet_need(a_type) == TechnologySpec.UnmetNeed.NONE


func use_resources_for(a_type: Variant) -> void:
	var technology_spec: TechnologySpec = technology_mapping.get(a_type)
	add_energy(-technology_spec.energy_cost)
	add_dominion(-technology_spec.dominion_cost)
	# Infrastructure is upkeep, not a one-time spend — it's adjusted when structures are
	# built/lost (see Commandable), not deducted per train.


## Refund the cost of `a_type` — the inverse of use_resources_for. Used when a queued
## training job is cancelled. A no-op for an unknown type. Infrastructure is upkeep (adjusted
## on build/loss), so nothing to refund there.
func refund_resources_for(a_type: Variant) -> void:
	var technology_spec: TechnologySpec = technology_mapping.get(a_type)
	if technology_spec == null:
		return
	add_energy(technology_spec.energy_cost)
	add_dominion(technology_spec.dominion_cost)


func proc_technology() -> void:
	# updates the tech tree of the commander according to changes in ownership.
	# A spec with no required_structures has all() return true → NONE.
	for tech: TechnologySpec in technology_mapping.values():
		tech.unmet_need = (
			TechnologySpec.UnmetNeed.NONE
			if tech.required_structures.all(func(t): return has_built_structure(t))
			else TechnologySpec.UnmetNeed.MISSING_STRUCTURE
		)


#endregion

#region Commandables

#region Structures
## piece id (StringName) -> Set of owned structures; entries appear lazily as
## structure ids are first seen (ids are open-ended, unlike the old enum).
var structure_type_map: Dictionary = {}


func _structures_of(a_id: StringName) -> Set:
	if not structure_type_map.has(a_id):
		structure_type_map[a_id] = Set.new()
	return structure_type_map[a_id]


func add_structure(a_structure: Commandable) -> void:
	_structures_of(a_structure.id).add(a_structure)
	proc_technology()


func remove_structure(a_structure: Commandable) -> void:
	_structures_of(a_structure.id).remove(a_structure)
	proc_technology()


#endregion


## Whether this commander still has anything in play — the basis for Scenario's implicit
## "you have been wiped out" loss. Three things it deliberately does NOT count:
##
## Why it works this way: gdd/systems/scenario-scripting/objectives-and-completion.md §What counts
## as still being in play.
func has_anything_in_play() -> bool:
	return _owned_commandables().any(
		func(c: Commandable) -> bool:
			return (
				not c.is_queued_for_deletion()
				and not c.is_planned
				and (c.selectable == null or c.selectable.is_reachable())
			)
	)


## Whether this commander holds a COMMAND CENTRE in play — what the HEGEMONY win condition
## (Scenario.win_condition) arms on and eliminates on. A blueprint is a plan, not a centre.
func owns_command_centre() -> bool:
	return _owned_commandables().any(
		func(c: Commandable) -> bool:
			return (
				Deployment.is_command_centre(c)
				and not c.is_queued_for_deletion()
				and not c.is_planned
			)
	)


## Set once this commander has been REMOVED FROM THE MATCH (HEGEMONY). Never cleared.
var is_eliminated: bool = false


## Remove this commander from the match: its brain stops thinking and every piece it still
## owns leaves play, freed rather than killed so nothing is paid out for them. Idempotent.
func eliminate() -> void:
	if is_eliminated:
		return
	is_eliminated = true
	var brain: BotBrain = get_node_or_null("BotBrain") as BotBrain
	if brain != null:
		brain.active = false
	for piece: Commandable in _owned_commandables():
		if not piece.is_queued_for_deletion():
			piece.queue_free()


## WHETHER THIS COMMANDER STILL HAS A BASE: at least one structure in play, or a purchase
## still on the production queue. The second half of the defeat rule — see
## gdd/systems/ai/bot-architecture.md §When a side is beaten.
##
## Why the rule needed widening beyond `has_anything_in_play`: that says a side is alive
## while it owns ONE straggler, and in the self-play corpus 23 of 61 stalemates were exactly
## that — a slot at zero structures riding a single surviving unit to the clock while the
## winner never hunted it down. A commander
## with no buildings cannot train, cannot expand and cannot come back, so scoring that as
## alive mis-records a match that was decided several minutes earlier.
##
## PRODUCTION, not structures alone, and that half is load-bearing: the last thing a
## flattened commander can still have is a purchase in flight — a funded Build whose builder
## is walking to the site. Ending the game on the structure count alone would cut off exactly
## the comeback the rule means to allow. A PLANNED structure is still not a foothold (same
## rule as above); the queue entry that funds it is what counts.
func has_production_base() -> bool:
	if production_queue != null and not production_queue.is_empty():
		return true
	return _owned_commandables().any(
		func(c: Commandable) -> bool:
			return c.structure_is_active() and not c.is_queued_for_deletion() and not c.is_planned
	)


#endregion


## The scenario's event host, where a sanction's payload is instantiated and run. Reached
## through the Scenario rather than held, so a commander in a rig without one (a test, the
## editor) simply has none and every caller degrades to "cannot fire".
func scenario_event_manager() -> ScenarioTriggerManager:
	if scenario == null or not is_instance_valid(scenario):
		return null
	return scenario.get_node_or_null("ScenarioTriggerManager") as ScenarioTriggerManager


## The sanctions this commandable may cast right now, given what the commander has
## unlocked. Empty when it is nobody's caster or the commander has no sanction grid.
func sanctions_castable_by(a_caster: Commandable) -> Array[Sanction]:
	if sanction_grid == null:
		return [] as Array[Sanction]
	return sanction_grid.castable_by(a_caster)


## Every owned, FINISHED piece granted `a_ability_id` — what an ability's HUD button
## selects when it is pressed, and what the order is then dispatched across.
##
## Asked of the ABILITY rather than of the sanction, because an ability need not have one:
## the Bombard's battery is granted by owning the gun (see AbilityCatalog).
func casters_of_ability(a_ability_id: StringName) -> Array:
	if String(a_ability_id).is_empty():
		return []
	return _owned_commandables().filter(
		func(c: Commandable) -> bool:
			if c.is_queued_for_deletion() or c.is_planned or not c.is_built:
				return false
			var abilities := c.get_node_or_null("Abilities") as Abilities
			return abilities != null and abilities.grants(a_ability_id)
	)


## The same question asked of a sanction, which is one route to one ability.
func casters_of(a_sanction: Sanction) -> Array:
	return casters_of_ability(a_sanction.ability_id) if a_sanction != null else []


## Abilities this commander has switched to MANUAL. Autocast is the default, so the set records
## the exceptions. A commander-wide setting rather than a per-piece one like hold fire: it says
## how the player wants the ability used, not what one piece is doing. Only an ability something
## casts on its own reads it — the Bombard, fired by a holding spotter (Bombard.autofire_on).
var _manual_abilities: Dictionary = {}


## Whether this commander's pieces cast `a_ability_id` on their own when something asks them to.
func is_autocasting(a_ability_id: StringName) -> bool:
	return not _manual_abilities.has(a_ability_id)


func set_autocast(a_ability_id: StringName, a_is_on: bool) -> void:
	if a_is_on:
		_manual_abilities.erase(a_ability_id)
	else:
		_manual_abilities[a_ability_id] = true


func toggle_autocast(a_ability_id: StringName) -> void:
	set_autocast(a_ability_id, not is_autocasting(a_ability_id))


## Every commandable this commander owns that can train anything.## Every commandable this commander
## owns that can train anything. What an unfenced
## purchase resolves against (see PurchaseTransaction.dispatch_filter): a train order given
## with nothing selected is eligible at any of these, and blueprints are INCLUDED because a
## unit ordered at a building that hasn't been started yet legitimately waits for it — the
## `is_built` gate belongs at dispatch (ready_producers), not here.
func owned_producers() -> Array:
	return _owned_commandables().filter(
		func(c: Commandable) -> bool: return not c.is_queued_for_deletion() and c.production != null
	)


## Owned, built structures that can receive deposited prisoners (e.g. a Compound) and still
## have room. Identified by a positive `sentence_length` (see Garrison.can_intern) — so any
## future holding structure is picked up automatically, while ordinary garrisons (a
## safehouse) are never mistaken for prisons.
##
## Lives on the base class rather than only on [Bot]: a human player's Stock Truck needs the
## same question answered for its own tasking (TaskShelter._nearest_available_compound).
func get_deposit_structures() -> Array:
	return _owned_commandables().filter(
		func(s: Commandable) -> bool:
			return (
				s.structure_is_active()
				and s.is_built
				and s.garrison != null
				and s.garrison.can_intern()
			)
	)


#region Unit tasking
## Monotonic per-commander counter for TaskShelter.sequence, stamped once per unit at the
## moment RTSController hands the order out (never by TaskShelter itself — sequencing is a
## fact about WHEN an order was given). The production queue's `sequence` is the precedent,
## and the reason is the same: positions and claims shift, so ordering has to be stamped
## rather than inferred. Never reset, so sequence numbers stay unique for this commander's
## whole life. See gdd/systems/commands/unit-tasking.md §Arbitration is by task age.
var _next_task_sequence: int = 1


func next_task_sequence() -> int:
	var sequence: int = _next_task_sequence
	_next_task_sequence += 1
	return sequence


## This commander's units currently tasked on `a_shelter` — a TaskShelter naming it
## somewhere in the unit's command chain (active or queued behind a pushed errand) — sorted
## OLDEST-tasked first. The arbitration `TaskShelter._errand_to_resident` reads each tick to
## decide which of several trucks working the same Shelter claims its next resident.
func trucks_tasked_on(a_shelter: Entity) -> Array[Commandable]:
	var sequence_of: Dictionary = {}
	for commandable: Commandable in _owned_commandables():
		if commandable.command_receiver == null:
			continue
		for command: MoveCommand in commandable.command_receiver.get_command_chain():
			var task := command as TaskShelter
			if task != null and task.message.target == a_shelter:
				sequence_of[commandable] = task.sequence
				break
	var tasked: Array[Commandable] = []
	tasked.assign(sequence_of.keys())
	tasked.sort_custom(
		func(a: Commandable, b: Commandable) -> bool:
			return int(sequence_of[a]) < int(sequence_of[b])
	)
	return tasked


#endregion


#region Airfields
## Every FINISHED airfield this commander owns. Blueprints and structures still going up
## are excluded — unlike a production order, which legitimately waits for its building, an
## aircraft sent to rearm needs a deck that exists right now.
func docking_bays() -> Array[DockingBay]:
	var result: Array[DockingBay] = []
	for c: Commandable in _owned_commandables():
		if c.is_queued_for_deletion() or c.is_planned or not c.is_built:
			continue
		if c.docking_bay != null:
			result.append(c.docking_bay)
	return result


## The airfield `unit` should head for: the closest one with a free pad, or — when every
## pad is taken — the closest that would admit it at all, so a unit sent out with all
## airfields busy queues at the nearest rather than refusing to go.
##
## Distance is measured to the airfield, not along a flight path, which for an aerial unit
## is the same thing.
func nearest_docking_bay_for(a_unit: Commandable) -> DockingBay:
	var best_free: DockingBay = null
	var best_free_d: float = INF
	var best_any: DockingBay = null
	var best_any_d: float = INF
	for bay: DockingBay in docking_bays():
		if not bay.admits(a_unit):
			continue
		var host: Commandable = bay.owner_commandable()
		if host == null:
			continue
		var d: float = VU.in_xz(a_unit.global_position).distance_to(VU.in_xz(host.global_position))
		if d < best_any_d:
			best_any_d = d
			best_any = bay
		if bay.has_free_pad() and d < best_free_d:
			best_free_d = d
			best_free = bay
	return best_free if best_free != null else best_any


## Total pads across every finished airfield this commander owns — the denominator of the
## capacity soft gate.
func total_docking_capacity() -> int:
	var total: int = 0
	for bay: DockingBay in docking_bays():
		total += bay.capacity()
	return total


## Aircraft this commander owns that need a pad to rearm at — anything that CAN dock and
## carries a CHARGED weapon. Both halves exclude real cases: a unit whose weapons reload on
## their own never docks however airborne it is, and an aircraft that opts out of airfields
## entirely (Movement.docks — the kamikaze drone) must not reserve a pad in the arithmetic,
## since it can never occupy one.
func charged_aircraft_count() -> int:
	var total: int = 0
	for c: Commandable in _owned_commandables():
		if c.is_queued_for_deletion() or c.is_planned:
			continue
		if c.docking == null:
			continue
		if c.weapon_inventory != null and c.weapon_inventory.has_charged_weapons():
			total += 1
	return total


## True when this commander has a pad spare for one more charged aircraft.
##
## A SOFT gate: Train.meets_precondition reads it to grey out and warn on the button, but
## nothing refuses the purchase — the player may deliberately field more aircraft than
## pads and accept that they queue for a deck when they run dry. That is the deliberate
## middle ground between free docking (no relationship between airfields and air force at
## all) and the Command & Conquer: Generals hard cap (a pad reserved for life at build
## time, so the airfield count IS the aircraft count).
##
## PENDING PIECES COUNT on both sides (see pending_pieces): an aircraft already ordered will take
## a pad, and an airfield already ordered will add them, so the gate answers for the force the
## player has committed to rather than the one standing this second.
func has_spare_docking_capacity() -> bool:
	var aircraft: int = charged_aircraft_count() + _count_pending(_needs_docking)
	var pads: int = total_docking_capacity() + roundi(_sum_pending(_pad_count_of))
	return aircraft < pads


## Whether `a_piece` would want a pad — the importer's flag on its tool, so an out-of-tree
## preview needs no loadout inspection.
static func _needs_docking(a_piece: Commandable) -> bool:
	var tool: Tool = Tool.for_type(a_piece.id)
	return tool != null and tool.needs_docking


static func _pad_count_of(a_piece: Commandable) -> float:
	var bay := a_piece.get_node_or_null("DockingBay") as DockingBay
	return float(bay.capacity()) if bay != null else 0.0


#endregion

#region Economy readouts
## Three figures about where this commander's energy is going. They PARTITION cleanly, which
## is the point: committed energy covers the queue side, spend rate covers the in-progress
## side, and neither double-counts the other. A spend rate that included the queue would
## overlap with committed energy and mislead in both directions.
##
## Committed energy is also what makes the two debit timings legible. A reject-mode purchase
## has already taken its energy out of the pool; a wait-mode one has not. Without a figure
## naming what has been promised, the resource display means different things depending on
## which mode the entries behind it were made in.


## Energy promised to purchases that are queued and not yet paid for. Reject-mode entries are
## excluded automatically rather than by a mode check: they debit at REQUEST time, so they
## are already out of `energy`, and their transaction is no longer PENDING. A standing entry is
## a template that soaks idle income rather than an order, so it promises nothing; each copy it
## issues is an ordinary purchase and is counted.
func energy_committed() -> int:
	var total: int = 0
	for transaction: PurchaseTransaction in production_queue.pending():
		if transaction.is_pending() and not transaction.standing:
			total += transaction.energy_cost
	return total


## The dominion equivalent. A purchase costs energy OR dominion, never both, so the two are
## disjoint sums over the same queue.
func dominion_committed() -> int:
	var total: int = 0
	for transaction: PurchaseTransaction in production_queue.pending():
		if transaction.is_pending() and not transaction.standing:
			total += transaction.dominion_cost
	return total


## Energy per second arriving from owned structures. Derived from the live EnergyExtractor
## components rather than sampled from the energy pool over a window: exact, and it responds
## the instant an extractor is finished or destroyed instead of lagging behind by the window.
##
## Less steady sources — faction-specific one-off acquisitions — are deliberately out of
## scope. This is the STEADY rate, which is what a clearance estimate can be computed
## against; folding a windfall into it would make the estimate wrong in both directions.
func energy_collection_rate() -> float:
	return _rate_over(_extraction_rate_of)


## Energy/s `a_piece` extracts once it runs. Reads its node rather than an @onready field, so it
## answers for an out-of-tree preview instance too (see pending_pieces).
static func _extraction_rate_of(a_piece: Commandable) -> float:
	var extractor := a_piece.get_node_or_null("EnergyExtractor") as EnergyExtractor
	if extractor == null:
		return 0.0
	return float(extractor.energy_rate) * TimeUtils.ticks_per_second() / EnergyExtractor.TICK_RATE


## Dominion per second from owned structures — the DominionGenerator equivalent.
func dominion_collection_rate() -> float:
	return _rate_over(_generation_rate_of) + _route_rate()


## Dominion/s `a_piece`'s own generator pays. payout() rather than the bare `dominion_rate`
## field: OccupantDominionGenerator (the Compound) scales payout() with its LIVE occupant count
## and leaves the inherited field at its unused script default.
static func _generation_rate_of(a_piece: Commandable) -> float:
	var generator := a_piece.get_node_or_null("DominionGenerator") as DominionGenerator
	if generator == null:
		return 0.0
	return float(generator.payout()) * TimeUtils.ticks_per_second() / DominionGenerator.TICK_RATE


## Dominion/s this commander's dominion route pays on its own sweep, beyond any generator
## component — the Libertarian Opticons' claim. 0 for a route that pays through generators.
func _route_rate() -> float:
	var route: DominionRoute = dominion_route()
	return route.collection_rate() if route != null else 0.0


## How many owned structures are extracting energy — the extractor count. Attribution for
## energy_collection_rate: a bare "+14/s" is trivia, "+14/s · 4 extractors" explains itself
## and tells
## the player what to do about it. Counted over the same set the rate sums over, so the two
## can never disagree about which structures are live.
func energy_source_count() -> int:
	return _count_over(
		func(c: Commandable) -> bool: return c.get_node_or_null("EnergyExtractor") != null
	)


## How many owned structures generate dominion. ZERO means there is no steady dominion rate
## to report at all, and the readout should omit the line rather than print "+0/s".
##
## That is what handles a faction whose dominion is EVENT-driven rather than per-tick —
## awarded for damage dealt to structures, say. Such a commander owns no DominionGenerator,
## so it reports no sources, no rate and no contributors, and needs no faction check
## anywhere: a rate sampled off combat damage would spike and flatline rather than describe
## anything, so not reporting one is the correct answer and it falls out of the count.
func dominion_source_count() -> int:
	return _count_over(
		func(c: Commandable) -> bool: return c.get_node_or_null("DominionGenerator") != null
	)


## What the dominion rate is made OF, summed across the commander's generators — prisoners
## held, units inside a warlord's range, whatever the faction's generator counts (see
## DominionGenerator.contributor_count). Returns DominionGenerator.NO_ATTRIBUTION when no
## generator reports a count, which is the readout's signal to show the rate alone.
func dominion_contributor_count() -> int:
	var total: int = 0
	var any_reported: bool = false
	for commandable: Commandable in _owned_commandables():
		if (
			commandable.is_queued_for_deletion()
			or commandable.is_planned
			or not commandable.is_built
		):
			continue
		var generator: DominionGenerator = (
			commandable.get_node_or_null("DominionGenerator") as DominionGenerator
		)
		if generator == null:
			continue
		var count: int = generator.contributor_count()
		if count == DominionGenerator.NO_ATTRIBUTION:
			continue
		any_reported = true
		total += count
	return total if any_reported else DominionGenerator.NO_ATTRIBUTION


## Steady-state dominion/s this commander's TASKED trucks would sustain, given where they
## are working right now — the number `DominionBar`'s forward-looking projection region
## reads, in place of `dominion_collection_rate()`'s instantaneous "what am I earning this
## instant" (see gdd/systems/ux/ui/economy-bars.md §Rate projection).
##
## `dominion_collection_rate()` stays correct for RIGHT NOW under sentences (the per-occupant
## payout is unchanged), but it is a poor predictor of the NEAR FUTURE: occupancy now decays
## as sentences complete, so "if this rate held" over-states the next minute unless arrivals
## keep pace. This answers a different question — "if my trucks keep working these Shelters
## at this distance, what does that sustain" — derived from live tasking rather than from
## occupancy history, which is silent about capacity a truck could still reach.
##
## One Shelter at a time (each is an independent source), summed. Per Shelter: round-trip
## time is travel there and back at the trucks' own speed (capacity, load and unload time
## are dropped — negligible for the one-truck-one-capacity openings this is aimed at, per
## design-framework/proposals.md §The model), giving an arrival rate capped by whichever is
## smaller, the Shelter's own regeneration or however many round trips the tasked trucks can
## make; that rate keeps `arrival_rate * sentence_length` captives serving, capped by how many
## the receiving Compound sentences at once (Garrison.SENTENCES_AT_ONCE) — the model's
## `min(Φ·τ, K)` with K the captives SERVING rather than held, since a captive waiting its turn
## pays nothing; without `m` or `μ` because one Shelter is asked to name the one Compound its
## own trucks would actually reach.
func projected_dominion_rate() -> float:
	var by_shelter: Dictionary = _trucks_by_tasked_shelter()
	# A route's own sweep pays a steady rate while its sources stand, so it projects as itself.
	var rate: float = _route_rate()
	for shelter: Entity in by_shelter:
		rate += _projected_rate_for_shelter(shelter, by_shelter[shelter])
	return rate


## This commander's tasked trucks, grouped by the Shelter each is tasked on.
func _trucks_by_tasked_shelter() -> Dictionary:
	var by_shelter: Dictionary = {}
	for commandable: Commandable in _owned_commandables():
		if commandable.command_receiver == null:
			continue
		for command: MoveCommand in commandable.command_receiver.get_command_chain():
			var task := command as TaskShelter
			if task == null or not is_instance_valid(task.message.target):
				continue
			var shelter: Entity = task.message.target
			if not by_shelter.has(shelter):
				by_shelter[shelter] = [] as Array[Commandable]
			(by_shelter[shelter] as Array[Commandable]).append(commandable)
			break
	return by_shelter


## One Shelter's contribution: `dominion_per_unit * min(arrival_rate * sentence_length,
## Garrison.SENTENCES_AT_ONCE)`, or 0.0 when there is nowhere for these trucks to deliver, the
## Shelter names no regeneration rate, or the trucks have none.
func _projected_rate_for_shelter(a_shelter: Entity, a_trucks: Array) -> float:
	var shelter := a_shelter.get_node_or_null("Shelter") as Shelter
	var compound: Commandable = SU.nearest_of(get_deposit_structures(), a_shelter)
	if shelter == null or shelter.spawn_interval <= 0.0 or compound == null or a_trucks.is_empty():
		return 0.0
	var truck_speed: float = 0.0
	for truck: Commandable in a_trucks:
		if truck.movement != null:
			truck_speed = truck.movement.speed
			break
	if truck_speed <= 0.0:
		return 0.0
	var distance: float = a_shelter.xz_position.distance_to(compound.xz_position)
	var round_trip_seconds: float = 2.0 * distance / truck_speed
	# A Compound built adjacent to its Shelter has nothing transport-side to bound the rate —
	# the trucks' own throughput is then unbounded and the Shelter's regeneration is the only
	# limit left, which is exactly what letting this term go to INF expresses.
	var truck_throughput: float = (
		float(a_trucks.size()) / round_trip_seconds if round_trip_seconds > 0.0 else INF
	)
	var arrival_rate: float = minf(1.0 / shelter.spawn_interval, truck_throughput)
	var sentence_length: float = compound.garrison.sentence_length
	var generator := compound.get_node_or_null("DominionGenerator") as OccupantDominionGenerator
	if generator == null or sentence_length <= 0.0:
		return 0.0
	var serving: float = minf(
		arrival_rate * sentence_length,
		float(mini(Garrison.SENTENCES_AT_ONCE, compound.garrison.capacity))
	)
	return float(generator.dominion_per_unit) * serving


## Energy per second flowing OUT into units currently being trained — each active job's cost
## spread over its build time.
##
## Computed from what is actively being trained, NOT from what is queued. Those are the two
## halves the readouts partition into: a queued purchase is committed energy, and only becomes
## a spend once a producer has actually started on it.
func energy_spend_rate() -> float:
	return _rate_over(
		func(c: Commandable) -> float:
			if c.production == null or c.production.is_free():
				return 0.0
			var spec: TechnologySpec = technology_mapping.get(c.production.job_type(0))
			var ticks: int = c.production.training_queue[0][Production.JOB_TOTAL]
			if spec == null or ticks <= 0:
				return 0.0
			return float(spec.energy_cost) * TimeUtils.ticks_per_second() / ticks
	)


## Sum `a_per_structure` over every built, non-blueprint structure this commander owns.
## Blueprints are excluded because a plan neither collects nor spends.
func _rate_over(a_per_structure: Callable) -> float:
	var total: float = 0.0
	for commandable: Commandable in _owned_commandables():
		if (
			commandable.is_queued_for_deletion()
			or commandable.is_planned
			or not commandable.is_built
		):
			continue
		total += a_per_structure.call(commandable) as float
	return total


## Count the built, non-blueprint structures this commander owns that satisfy `a_predicate`.
## Same exclusions as _rate_over, so an attribution count and the rate it explains always
## describe the same set of structures.
func _count_over(a_predicate: Callable) -> int:
	var total: int = 0
	for commandable: Commandable in _owned_commandables():
		if (
			commandable.is_queued_for_deletion()
			or commandable.is_planned
			or not commandable.is_built
		):
			continue
		if a_predicate.call(commandable):
			total += 1
	return total


## How long, in seconds, until the queue's committed energy is covered by net income — or -1.0
## when it never will be at the current rate. What "clears in ~40s" is computed from.
##
## Measured against NET income (collection minus what training is already drawing), because
## committed energy has to be paid on top of production that is already running. A non-positive
## net means the commitment is not being paid down at all, which is exactly the state worth
## flagging rather than papering over with a large number.
func energy_clearance_seconds() -> float:
	var owed: int = energy_committed() - energy
	if owed <= 0:
		return 0.0
	var net: float = energy_collection_rate() - energy_spend_rate()
	if net <= 0.0:
		return -1.0
	return float(owed) / net


#endregion


#region Pending pieces
## What this commander has ORDERED that is not active yet — the HUD's "will happen" layer (see
## gdd/systems/ux/README.md §Pending pieces are shown, as pending). One entry per piece:
##   * blueprints and structures still going up — the real nodes;
##   * one-off purchases still in the production queue (a TRAIN, or a BUILD whose blueprint is
##     not up), and every unit a producer has started on — the tool's cached OUT-OF-TREE preview
##     instance (get_build_preview_instance), once per order, so ten queued Recruits are ten
##     entries of one instance.
## A preview never entered the tree, so read its exports and nodes, never its @onready fields.
## A standing entry is a policy, not an order, and is left out.
func pending_pieces() -> Array[Commandable]:
	# Memoized per frame: every economy bar and each aircraft button asks, every frame, and each
	# answer is a walk over every owned piece and the whole queue. Keyed on the piece and queue
	# counts as well, so an order placed earlier in the same frame is not missed.
	var key: Array = [
		Engine.get_process_frames(),
		get_child_count(),
		production_queue.entries.size() if production_queue != null else 0
	]
	if key != _pending_pieces_key:
		_pending_pieces_key = key
		_pending_pieces = _collect_pending_pieces()
	return _pending_pieces


var _pending_pieces_key: Array = []
var _pending_pieces: Array[Commandable] = []


func _collect_pending_pieces() -> Array[Commandable]:
	var out: Array[Commandable] = []
	for piece: Commandable in _owned_commandables():
		if piece.is_queued_for_deletion():
			continue
		if piece.is_planned or not piece.is_built:
			out.append(piece)
		elif piece.production != null:
			for i: int in piece.production.job_count():
				_append_preview(out, Tool.for_type(StringName(str(piece.production.job_type(i)))))
	if production_queue == null:
		return out
	for transaction: PurchaseTransaction in production_queue.pending():
		if transaction.standing or transaction.is_settled():
			continue
		if (
			transaction.kind == PurchaseTransaction.Kind.BUILD
			and is_instance_valid(transaction.planned_structure)
		):
			continue  # its blueprint is already in `out`
		_append_preview(out, transaction.tool)
	return out


func _append_preview(a_out: Array[Commandable], a_tool: Tool) -> void:
	var preview := get_build_preview_instance(a_tool) as Commandable if a_tool != null else null
	if preview != null:
		a_out.append(preview)


## `a_value` summed over pending_pieces.
func _sum_pending(a_value: Callable) -> float:
	var total: float = 0.0
	for piece: Commandable in pending_pieces():
		total += a_value.call(piece) as float
	return total


## How many pending_pieces satisfy `a_predicate`.
func _count_pending(a_predicate: Callable) -> int:
	return pending_pieces().filter(a_predicate).size()


## Infrastructure capacity pending pieces will add once they are up.
func pending_infrastructure_provided() -> int:
	return roundi(
		_sum_pending(func(p: Commandable) -> float: return float(maxi(p.infrastructure, 0)))
	)


## Infrastructure upkeep pending pieces will add once they are up.
func pending_infrastructure_required() -> int:
	return roundi(
		_sum_pending(func(p: Commandable) -> float: return float(maxi(-p.infrastructure, 0)))
	)


## Energy/s the pending extractors will add once they run.
func pending_energy_collection_rate() -> float:
	return _sum_pending(_extraction_rate_of)


## Dominion/s the pending generators will add once they run, plus what the route's pending
## sources will change — which is negative when a planned building will cover paying ground.
func pending_dominion_collection_rate() -> float:
	var route: DominionRoute = dominion_route()
	var route_delta: float = route.pending_rate_change() if route != null else 0.0
	return _sum_pending(_generation_rate_of) + route_delta


## Cells the footprints of this side's planned buildings will take — blueprints no builder has
## laid yet, which hold no grid cells but have claimed the site. `a_except` is left out (the
## order asking about its own site). Read by placement: a site something on our side already
## means to build on is refused (see Build.meets_precondition).
## PLANNED — ALLIES: only this commander's blueprints until alliances land (shares_side_with).
func planned_footprint_cells(a_except: Commandable = null) -> Dictionary:
	var out: Dictionary = {}
	if map == null:
		return out
	for piece: Commandable in _owned_commandables():
		if piece == a_except or not piece.is_planned or piece.is_queued_for_deletion():
			continue
		var obs := piece.get_node_or_null("Structure") as Structure
		var dims: Vector2i = obs.footprint_dimensions() if obs != null else Vector2i.ONE
		for cell: Vector2i in map.footprint_cells(VU.in_xz(piece.global_position), dims):
			out[cell] = true
	return out


#endregion

#region Build previews
## Live, out-of-tree instances of each buildable structure, kept so the build
## "ghost" can reference a team-tinted version of the real building art. Keyed by
## piece id. These are deliberately NOT added to the SceneTree (so their
## _ready / physics / fog / auto-init logic never runs and they're never
## registered as real structures); because they're orphaned, we free them
## explicitly on PREDELETE. Instantiating them through the Commander also means
## runtime changes to a building type (e.g. an upgraded sprite) flow through to
## the preview automatically.
var _build_preview_instances: Dictionary = {}


## Return (creating and caching on first use) a live, team-tinted instance of the
## structure for the given Tool, for use as a placement-preview source. The
## instance carries this commander's tint via configure_preview_ownership. Never
## added to the tree. Returns null if the tool has no packed scene.
func get_build_preview_instance(a_tool: Tool) -> Node:
	if a_tool == null or a_tool.packed_scene == null:
		return null
	# One instance per VARIANT of a piece: the variants differ in footprint, HP and infrastructure.
	# An unbound tool of such a piece previews its default.
	var tool: Tool = a_tool.resolved()
	var cached: Variant = _build_preview_instances.get(tool.preview_key())
	if cached != null and is_instance_valid(cached):
		return cached
	var instance: Node = tool.instantiate()
	if instance is Entity:
		(instance as Entity).configure_preview_ownership(self)
	_build_preview_instances[tool.preview_key()] = instance
	return instance


func _notification(a_what: int) -> void:
	if a_what == NOTIFICATION_PREDELETE:
		for inst in _build_preview_instances.values():
			if is_instance_valid(inst):
				inst.free()
		_build_preview_instances.clear()
		if blackboard != null:
			blackboard.free_visuals()


#endregion


#region Perception queries (fog-limited)
# Entity.initialize() calls commander.add_child(entity), so every owned entity is a
# direct child of this node. get_children() is therefore the authoritative source
# for owned-entity queries, and requires no scene-tree scan.
func _owned_commandables() -> Array:
	return get_children().filter(func(n): return n is Commandable)


## Owned entities that contribute VISION right now — see Entity.grants_vision.
## Broader than _owned_commandables(): it also includes non-Commandable vision
## sources such as the Scout spawned by the Radar Scan sanction. Geometric-vision
## queries (visible_enemies / has_vision_at, and through it visible_foreign_structures
## and the blackboard's snapshot/belief memory) iterate THIS set so they match the fog
## texture — fog.gd likewise reveals for any entity with a vision_range_shape, not just
## Commandables. Without this a Scout would poke a hole in the fog but never trigger the
## sight checks that record structure snapshots.
func _owned_vision_sources() -> Array:
	return get_children().filter(func(n): return n is Entity and (n as Entity).grants_vision())


# Gathers all commandables owned by an arbitrary list of commanders using the same
# child-based convention.
func _commandables_of(a_commanders: Array) -> Array:
	var result: Array = []
	for c: Commander in a_commanders:
		for child in c.get_children():
			if child is Commandable:
				result.append(child)
	return result


# Every Commander with id != 0 (neutral) and id != self.id is an enemy.
func _enemy_commanders() -> Array:
	if scenario == null:
		return []
	return scenario.commanders.filter(func(c: Commander): return c.id != id and c.id != 0)


## All enemy commandables within [radius] world units of [position]. An ENEMY is
## owned by a different, non-neutral commander (excluding neutral id 0 matches
## _enemy_commanders).
##
## OMNISCIENT: a physics overlap, so it returns fogged and stealthed enemies too. It is the
## primitive under visible_enemies(), which adds the fog gate; anything that models what
## this commander KNOWS reads visible_enemies_near instead. The bot's threat senses once
## read this directly and so defended against units nobody could see (world-model.md
## §The fog boundary).
func get_enemies_near(a_position: Vector3, a_radius: float) -> Array:
	if map == null:
		return []
	var nearby: Array = SU.get_nearby_entities(
		map.get_world_3d(), a_position, a_radius, CollisionLayers.TARGETABLE_ANY
	)
	return nearby.filter(
		func(e): return e is Commandable and e.commander_id != id and e.commander_id != 0
	)


## The enemies within [radius] of [position] that this commander can SEE — get_enemies_near
## behind the same fog-and-stealth gate visible_enemies() applies. The one radius query a
## perception read may use.
func visible_enemies_near(a_position: Vector3, a_radius: float) -> Array:
	return get_enemies_near(a_position, a_radius).filter(
		func(e): return (e as Commandable).is_visible_to(id)
	)


## Structures currently within this commander's vision that it does NOT own —
## INCLUDING neutral (id 0) ones (extractors, mountains, Shelters, ExtractionSites). Unlike
## visible_enemies(), this deliberately keeps neutral structures so the snapshot
## memory remembers them too. "Structure" means an entity carrying a Structure
## component (grid-occupying footprint) — NOT necessarily a Commandable: Shelters and
## ExtractionSites derive from Entity, so gate on structure_is_active(), not `is Commandable`.
## Uses the "fixture" group + Fog.structure_in_vision (the SAME any-footprint-cell
## fog check fog.gd uses to reveal a structure), so it needs no targetable collision
## layer (neutral structures may not be on one), and a structure is deemed "seen"
## here on exactly the frames fog reveals it.
func visible_foreign_structures() -> Array:
	var result: Array = []
	var fog: Fog = _fog()
	for s in get_tree().get_nodes_in_group("fixture"):
		# A structure is seen when ANY of its footprint cells is revealed (the same
		# any-cell rule fog.gd uses to show it) — not just the cell under its origin.
		# is_planned skips another commander's blueprints: they aren't physically there, so
		# they're neither perceivable nor worth remembering as a fog-of-war snapshot.
		if (
			s.structure_is_active()
			and s.commander_id != id
			and not s.is_planned
			and (fog == null or fog.structure_in_vision(s))
		):
			result.append(s)
	return result


## Enemy commandables this commander can currently SEE: those within the VisionRange
## of any owned unit or structure. Deduplicated. This is the fog-of-war boundary for
## belief updates — it must not "cheat" by reading enemies the commander can't see.
func visible_enemies() -> Array:
	var result: Array = []
	var seen: Dictionary = {}
	for owned: Entity in _owned_vision_sources():
		var vr: float = _shape_xz_radius(owned.vision_range_shape)
		if vr <= 0.0:
			continue
		for e in get_enemies_near(owned.global_position, vr):
			if not seen.has(e) and (e as Commandable).is_visible_to(id):
				seen[e] = true
				result.append(e)
	return result


## True when the fog pixel covering [world_pos] is currently revealed in this
## commander's fog — the SAME pixel-quantized disc fog.gd uses, NOT a geometric
## distance (which would disagree with the rasterized disc at the boundary). Used
## for point checks against a remembered structure location (belief aging, snapshot
## re-scout). For a live structure's own visibility use Fog.structure_in_vision,
## which tests its whole footprint. Returns true when this commander has no fog.
func has_vision_at(a_world_pos: Vector3) -> bool:
	var fog: Fog = _fog()
	if fog == null:
		return true
	return fog.fog_clear_at(VU.in_xz(a_world_pos))


## True when [world_pos] has ever been in this commander's vision — what it can know is on
## the map without having been told. Returns true when this commander has no fog, as
## has_vision_at does.
func has_explored(a_world_pos: Vector3) -> bool:
	var fog: Fog = _fog()
	if fog == null:
		return true
	return fog.explored_at(VU.in_xz(a_world_pos))


## This commander's Fog of war. Null for a commander with no Fog (the neutral/world owner,
## or no rig / editor).
func _fog() -> Fog:
	return Fog.for_commander(id)


## Whether this commander's vision is tracked at all. `has_vision_at` answers true with no fog
## (nothing is hidden from a commander with none), which a caller asking "is this ground
## already watched" must not read as "yes".
func has_fog() -> bool:
	return _fog() != null


## World-space XZ radius of [entity]'s VisionRange — the SAME reveal radius the fog
## of war uses (fog.gd reads vision_range_shape identically). 0 when the entity has
## no vision shape.
func vision_radius(a_entity: Entity) -> float:
	return _shape_xz_radius(a_entity.vision_range_shape) if a_entity != null else 0.0


## XZ radius of a CollisionShape3D (cylinder/sphere radius × node X-scale), or 0.
func _shape_xz_radius(a_shape_node: CollisionShape3D) -> float:
	if a_shape_node == null:
		return 0.0
	var scale: float = a_shape_node.global_transform.basis.x.length()
	var shp: Shape3D = a_shape_node.shape
	if shp is CylinderShape3D:
		return (shp as CylinderShape3D).radius * scale
	if shp is SphereShape3D:
		return (shp as SphereShape3D).radius * scale
	return 0.0


## Seconds elapsed since the scenario started, from the physics-tick counter. The rate is
## TimeUtils', never restated here.
func seconds_elapsed() -> float:
	if scenario == null:
		return 0.0
	return TimeUtils.seconds_from_ticks(scenario.tick)


#endregion


#region Node
func _ready() -> void:
	_instance_faction()
	# Drive the HUD resource bars off resource changes rather than polling them
	# every frame (see resources_changed). Paint once now for the initial values.
	resources_changed.connect(_refresh_resource_bars)
	_refresh_resource_bars()

	# Runtime-only perception setup. Commander is @tool, so guard against the editor
	# (where there's no live Scenario to walk up to).
	if Engine.is_editor_hint():
		return
	_resolve_scene_references()
	# The neutral world commander (id 0) never views and has no strategic beliefs,
	# so it needs no blackboard or snapshots.
	if id != 0:
		blackboard = CommanderBlackboard.new(self)
	# Run this commander's _physics_process AFTER fog.gd's (default priority 0), so the
	# snapshot visibility swap reads each real structure's freshly-updated `visible`
	# this frame — making the memory the exact complement of what fog shows.
	process_physics_priority = 100


## Resolve [map] and [scenario] from the expected position Scenario/Players/<self>.
## Scenario._ready() places all commanders under a "Players" node that is a direct
## child of Scenario, so two get_parent() calls suffice. No-ops on already-set refs
## (e.g. injected via initialize()).
func _resolve_scene_references() -> void:
	var players := get_parent()
	if players != null and scenario == null:
		scenario = players.get_parent() as Scenario
	if scenario != null and map == null:
		map = scenario.map


## Explicit injection alternative to the tree-walk in _ready(), for when references
## must be wired before any _ready() callbacks fire.
func initialize(a_map: Map, a_scenario: Scenario) -> void:
	map = a_map
	scenario = a_scenario


func _physics_process(_a_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	# Ahead of the blackboard guard below: the queue is economy, not perception, so it
	# must keep fulfilling purchases for a commander that has neither (e.g. the neutral
	# world commander, or before the map resolves).
	production_queue.tick()
	if blackboard == null or map == null:
		return
	# The player-facing snapshot layer (creation + visibility) runs EVERY frame
	# (cheap: a handful of structures, fog-pixel lookups only), so a remembered
	# structure appears the exact frame fog hides the real one — no gap or lag. It
	# reads each real structure's fog-driven `visible`, so it must run AFTER fog:
	# see process_physics_priority in _ready.
	blackboard.refresh_snapshots()
	# The AI-only belief refresh (visible_enemies physics queries + aging) is the
	# heavy, non-player-facing part, so it's throttled to ~5 Hz.
	_ticks_since_blackboard += 1
	if _ticks_since_blackboard < BLACKBOARD_TICK_INTERVAL:
		return
	_ticks_since_blackboard = 0
	blackboard.update()


## Instance this commander's faction_scene as a child and cache it in `faction`.
## A null faction_scene is legitimate ONLY for the neutral world commander (id 0),
## which has no player slot; every slot-built commander is guaranteed one by
## Scenario._validate_player_slots.
func _instance_faction() -> void:
	if faction_scene == null:
		return
	var instance: Node = faction_scene.instantiate()
	faction = instance as Faction
	add_child(instance)
	if faction != null:
		sanction_grid = SanctionGrid.new(self, faction.sanction_unlocks)


## Repaint the persistent resource bars. Only the human-controlled commander carries the HUD
## rig (Controller + the three bars), and it can now be any id — or none, in spectator mode.
## Gate on each node actually existing rather than a hardcoded id so bots (and the neutral
## commander) don't try to write panels they don't have.
##
## Each bar also repaints itself every frame — it has to, since its rates move with no
## resource-change signal behind them. This push is kept so a resource change is reflected in
## the same frame it happens rather than on the next one.
func _refresh_resource_bars() -> void:
	var dominion_bar := get_node_or_null("Controller/DominionBar") as DominionBar
	if dominion_bar != null:
		dominion_bar.refresh()
	var energy_bar := get_node_or_null("Controller/EnergyBar") as EnergyBar
	if energy_bar != null:
		energy_bar.refresh()
	var infrastructure_bar := get_node_or_null("Controller/InfrastructureBar") as InfrastructureBar
	if infrastructure_bar != null:
		infrastructure_bar.refresh()
#endregion
