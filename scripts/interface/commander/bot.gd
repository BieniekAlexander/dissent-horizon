class_name Bot
extends Commander

## Bot — perception layer for a CPU-controlled commander.
##
## This script is a pure observation module: it exposes read-only query
## functions (the "senses") that a future AI strategy layer will call to
## understand game state before deciding what to do.  No decision-making
## or command-issuing logic belongs here.
##
## Scene placement: Bot expects to live at Scenario/Players/<bot>. Commander._ready()
## auto-resolves [map] and [scenario] (both live on Commander now) by walking up the
## tree, and owns the fog-limited perception surface and the CommanderBlackboard.

# ─── INTERNAL HELPERS ───────────────────────────────────────────────────────

# A structure carries a "Structure" component (declaring its grid footprint); a
# mobile unit does not. Presence of that child node — NOT the Entity.Type — is the
# bot's unit/structure discriminator, so new scenes classify correctly without any
# type-table edits.
func _owned_units() -> Array:
	return _owned_commandables().filter(
		func(c: Commandable): return not c.has_node("Structure")
	)

func _owned_structures() -> Array:
	return _owned_commandables().filter(
		func(c: Commandable): return c.has_node("Structure")
	)


# ─── ECONOMY ────────────────────────────────────────────────────────────────

## True when ore reserves are at or above [threshold].
## Use this to gate build decisions: "only expand if ore_is_above(400)".
func ore_is_above(threshold: int) -> bool:
	return ore >= threshold


## Vigor surplus below which the bot should stand up its faction vigor provider
## before expanding further — roughly one unit-producing structure's upkeep, so it
## builds power proactively rather than waiting until it's already strained.
const VIGOR_PROVIDER_MARGIN: int = 40

## True when the commander lacks the headroom to add another vigor-consuming
## structure — the cue for BotEconomy to build a vigor provider before more buildings.
func needs_vigor_provider() -> bool:
	return vigor < VIGOR_PROVIDER_MARGIN


## The number of owned Mines that are fully built.  Serves as a relative income
## index — partially-built mines are excluded because they don't yet extract ore.
func mine_count() -> int:
	# A mine is a built structure that extracts ore — identified by its OreExtractor
	# component rather than by Entity.Type.
	return _owned_structures().filter(
		func(s: Commandable): return s.has_node("OreExtractor") and s.is_built
	).size()


## True when the bot has both the prerequisite tech unlock AND enough ore /
## vigor / dominion to produce [type] right now.
func can_afford(type: StringName) -> bool:
	return has_resources_for(type)


## Every Entity.Type the bot can immediately produce (tech unlocked + resources
## available).  The strategy layer can iterate this to pick what to build next.
func affordable_types() -> Array:
	return technology_mapping.keys().filter(func(t): return has_resources_for(t))


# ─── OWNED ENTITY QUERIES ───────────────────────────────────────────────────

## All units this commander currently owns.
func get_units() -> Array:
	return _owned_units()


## The scene resource path that [type] is produced from, or "" when no build/train
## tool registers it. Lets the bot match owned instances to a catalog type by their
## scene (a node property) instead of reading each instance's Entity.Type.
func _scene_path_for_type(type) -> String:
	var tool: Tool = Tool.for_type(type)
	return tool.packed_scene.resource_path if tool != null and tool.packed_scene != null else ""


## All units of a specific type (e.g. only Vanguards, only Irregulars). Matches by
## the unit's source scene rather than by inspecting its Entity.Type.
func get_units_of_type(type: StringName) -> Array:
	var scene_path := _scene_path_for_type(type)
	if scene_path == "":
		return []
	return _owned_units().filter(func(c: Commandable): return c.scene_file_path == scene_path)


## All structures of a specific type.  Wraps structure_type_map for
## convenience so callers don't need to call .get_values() themselves.
func get_structures_of_type(type: StringName) -> Array:
	var s: Variant = structure_type_map.get(type)
	return s.get_values() if s != null else []


## Structures that have a Production component AND are fully built, meaning they
## can currently train units. Under-construction structures are excluded because
## production.tick() is gated on is_built and their queues won't advance.
func get_production_structures() -> Array:
	return _owned_structures().filter(
		func(s: Commandable): return s.production != null and s.is_built
	)


## Production-capable structures whose training queue is currently empty.
## Each one represents wasted throughput that the bot should fill.
func get_idle_production_structures() -> Array:
	return get_production_structures().filter(
		func(s: Commandable): return s.production.training_queue.is_empty()
	)


## Units with no active command — standing idle and available to be re-tasked.
func get_idle_units() -> Array:
	return _owned_units().filter(func(c: Commandable): return not c.has_command())


## Total number of units owned by this commander.
func army_size() -> int:
	return _owned_units().size()


## Total ore value of the owned army — sum of each unit's build cost (its
## technology_mapping ore_cost). Used by the military as the "how much have I
## invested in an army" gauge that drives attack-wave commitment.
func army_resource_value() -> float:
	var total: float = 0.0
	for u: Commandable in _owned_units():
		var spec: TechnologySpec = technology_mapping.get(u.id)
		if spec != null:
			total += spec.ore_cost
	return total


## Maps unit scene path → count for each kind of unit the bot owns. Keyed by the
## source scene (a node property) rather than Entity.Type, so it gauges army
## composition without inspecting each unit's type.
func army_type_counts() -> Dictionary:
	var counts: Dictionary = {}
	for c: Commandable in _owned_units():
		counts[c.scene_file_path] = counts.get(c.scene_file_path, 0) + 1
	return counts


# ─── ARMY HEALTH ────────────────────────────────────────────────────────────

## Average HP fraction (0.0 – 1.0) across all owned units.
## 1.0 means every unit is at full health; values below 0.5 suggest the
## army needs to disengage and recover before the next fight.
func army_average_health_fraction() -> float:
	var units := _owned_units()
	if units.is_empty():
		return 0.0
	var total := 0.0
	for c: Commandable in units:
		total += c.defense.hp / c.defense.hp_max if c.defense != null else 0.0
	return total / float(units.size())


## Rough combat-power score: sum of (DAMAGE × HP-fraction) for all owned
## units.  Captures both quantity and health state in a single number.
## Intended for relative comparisons (e.g. vs. estimate_enemy_strength()),
## not as an absolute damage-per-second figure.
func estimate_army_strength() -> float:
	var strength := 0.0
	for c: Commandable in _owned_units():
		if c.defense == null: continue
		strength += (c.weapon_inventory.total_damage() if c.weapon_inventory != null else 0.0) * (c.defense.hp / c.defense.hp_max)
	return strength


# ─── THREAT ASSESSMENT ──────────────────────────────────────────────────────

## All commandables (units and structures) belonging to enemy commanders.
func get_all_enemies() -> Array:
	return _commandables_of(_enemy_commanders())


## Only the mobile units owned by enemy commanders — the things that attack.
func get_enemy_units() -> Array:
	return get_all_enemies().filter(
		func(c: Commandable): return not c.has_node("Structure")
	)


## Only the structures owned by enemy commanders — the things to destroy.
func get_enemy_structures() -> Array:
	return get_all_enemies().filter(
		func(c: Commandable): return c.has_node("Structure")
	)


## Enemy commandables within [unit]'s aggro range, keeping only targets ranked at least
## as important as [min_target_priority] and sorting them by target priority (most
## important first). Uses the unit's actual aggro shape via SU.entities_in_aggro_shape —
## the same check Commandable.get_aggro_near_position runs. Empty when the unit has no
## aggro_range_shape.
func get_enemies_in_aggro_range(unit: Commandable, \
		min_target_priority: Entity.TargetPriority = Entity.TargetPriority.NON_COMBAT_UNITS) -> Array:
	var enemies: Array = SU.entities_in_aggro_shape(
		unit.get_world_3d(), unit.aggro_range_shape, unit.global_position, unit.target_body
	).filter(func(e): return e is Commandable and e.commander_id != id and e.commander_id != 0 \
		and e.target_priority <= min_target_priority)
	enemies.sort_custom(func(a: Entity, b: Entity): return a.target_priority < b.target_priority)
	return enemies


## Enemy units within [threat_radius] world units of any owned structure.
## Non-empty means the base is being actively pressured.  Deduplicates
## enemies that are close to several structures at once.
## NOTE: intentionally includes unbuilt structures — an enemy attacking a
## structure under construction is still a threat worth responding to.
func get_enemies_threatening_base(threat_radius: float = 30.0) -> Array:
	if map == null:
		return []
	var seen: Dictionary = {}
	var threats: Array = []
	for s: Commandable in _owned_structures():
		for enemy: Commandable in get_enemies_near(s.global_position, threat_radius):
			if not seen.has(enemy):
				seen[enemy] = true
				threats.append(enemy)
	return threats


## True when at least one enemy unit is within [threat_radius] of any
## owned structure.
func is_base_under_threat(threat_radius: float = 30.0) -> bool:
	return not get_enemies_threatening_base(threat_radius).is_empty()


## The owned structure most in danger: lowest HP fraction among those
## that currently have enemies nearby.  Returns null if nothing is under
## active attack.  A natural rally target for defensive units.
func most_threatened_structure(threat_radius: float = 30.0) -> Commandable:
	var worst: Commandable = null
	var worst_frac := 1.0
	for s: Commandable in _owned_structures():
		if not get_enemies_near(s.global_position, threat_radius).is_empty():
			var frac := s.defense.hp / s.defense.hp_max if s.defense != null else 0.0
			if frac < worst_frac:
				worst_frac = frac
				worst = s
	return worst


## Normalized threat rating from 0.0 (no threat) to 1.0 (outgunned).
## Computed as enemy_strength / (own_strength + enemy_strength), where
## strength is the estimate_army_strength() calculation applied to each side.
## Values above 0.5 mean the enemy army is currently stronger than ours.
func relative_threat_level() -> float:
	var enemy_strength := 0.0
	for c: Commandable in get_enemy_units():
		if c.defense == null: continue
		enemy_strength += (c.weapon_inventory.total_damage() if c.weapon_inventory != null else 0.0) * (c.defense.hp / c.defense.hp_max)
	var own := estimate_army_strength()
	var total := own + enemy_strength
	if total == 0.0:
		return 0.0
	return enemy_strength / total


# ─── SPATIAL / MAP AWARENESS ────────────────────────────────────────────────

## Average world position of all owned units — the army's center of mass.
## Returns Vector3.ZERO when no units exist.  Useful for picking a rally
## point or choosing a direction of attack.
func army_centroid() -> Vector3:
	var units := _owned_units()
	if units.is_empty():
		return Vector3.ZERO
	var sum := Vector3.ZERO
	for c: Commandable in units:
		sum += c.global_position
	return sum / float(units.size())


## Average world position of all owned structures — a rough "home base"
## anchor.  Returns Vector3.ZERO when no structures exist.
## NOTE: includes unbuilt structures (they occupy real space and anchor the base).
func base_centroid() -> Vector3:
	var all_s: Array = _owned_structures()
	if all_s.is_empty():
		return Vector3.ZERO
	var sum := Vector3.ZERO
	for s: Commandable in all_s:
		sum += s.global_position
	return sum / float(all_s.size())


## Owned, fully-built structures that have a Garrison component with remaining space.
func get_garrison_structures() -> Array:
	return _owned_structures().filter(
		func(s: Commandable) -> bool:
			return s.is_built and s.garrison != null and s.garrison.can_garrison()
	)


## The nearest owned garrison structure with available space to [unit], or null
## when the bot owns none. Used by preservation to garrison at-risk units.
func nearest_garrison_for(unit: Commandable) -> Commandable:
	var hosts: Array = get_garrison_structures()
	if hosts.is_empty():
		return null
	return AU.sort_on_key(
		func(s: Commandable): return unit.global_position.distance_squared_to(s.global_position),
		hosts
	).front()


## The owned structure nearest to [from], or null when the bot owns none.
## Used by BotPreservation as the retreat waypoint for at-risk units.
func nearest_own_structure(from: Vector3) -> Commandable:
	var structs: Array = _owned_structures()
	if structs.is_empty():
		return null
	return AU.sort_on_key(
		func(s: Commandable): return from.distance_squared_to(s.global_position),
		structs
	).front()


## The enemy structure closest to our base centroid.
## Attacking the nearest enemy building minimises exposure while applying
## economic pressure.  Returns null when no enemy structures exist.
func nearest_enemy_structure_to_base() -> Commandable:
	var enemies := get_enemy_structures()
	if enemies.is_empty():
		return null
	var base := base_centroid()
	return AU.sort_on_key(
		func(s: Commandable): return base.distance_squared_to(s.global_position),
		enemies
	).front()


## Mines still owned by the neutral commander (id == 0) — uncontested
## resource nodes worth sending a Technician to capture.
func get_neutral_mines() -> Array:
	if scenario == null:
		return []
	var neutrals := scenario.commanders.filter(
		func(c: Commander): return c.id == 0
	)
	if neutrals.is_empty():
		return []
	var neutral: Commander = neutrals.front()
	# A mine is identified by its OreExtractor component, not by Entity.Type.
	return neutral.get_children().filter(
		func(n): return n is Commandable and n.has_node("OreExtractor")
	)


## The neutral Mine closest to [from_position].
## Returns null when every Mine on the map has already been claimed.
func nearest_neutral_mine(from_position: Vector3) -> Commandable:
	var mines := get_neutral_mines()
	if mines.is_empty():
		return null
	return AU.sort_on_key(
		func(m: Commandable): return from_position.distance_squared_to(m.global_position),
		mines
	).front()


# ─── INTERACTIONS (utility-gain opportunities) ──────────────────────────────

## Owned units that can perform interactions — those carrying an Interactor component
## (e.g. Warlords, who can liberate Shelters). The set the opportunist draws liberators
## from; identified by the component, so any future interactor unit is picked up.
func get_interactors() -> Array:
	return _owned_units().filter(func(u: Commandable): return u.interactor != null)


## Every Shelter on the map currently available to interact with (its startup countdown
## has elapsed). Shelters are fixed neutral map features, so — like neutral mines — the
## bot is aware of them regardless of fog. Returns the Shelter-bearing Entities (a
## ShelterStructure derives from Entity, not Commandable — it takes no commands).
func get_available_shelters() -> Array:
	return get_tree().get_nodes_in_group("shelter").filter(
		func(n: Node) -> bool:
			var s := n.get_node_or_null("Shelter") as Shelter
			return s != null and s.available
	)


## Owned, built structures with inventory space to receive deposited units (e.g. an
## internment camp). Identified by the Inventory component, so any future deposit
## structure is picked up automatically.
func get_deposit_structures() -> Array:
	return _owned_structures().filter(
		func(s: Commandable) -> bool:
			if not s.is_built:
				return false
			var inv := s.get_node_or_null("Inventory") as Inventory
			return inv != null and inv.can_hold_more()
	)


## Visible enemy units the bot can capture: biological-frame, non-structure, owned by
## an enemy. Fog-limited (visible_enemies only). The Colonial stock truck imprisons
## these for dominion.
func get_capturable_enemies() -> Array:
	return visible_enemies().filter(
		func(e: Commandable) -> bool:
			return not e.has_node("Structure") \
				and EntityAttribute.evaluate(EntityAttribute.Type.IS_BIOLOGICAL, e)
	)


## Ore value of the units an Interaction's event scene would spawn for us — sums
## unit_cost(type) × count across every EventSpawnEntities in the event. This is the raw
## utility GAIN of performing the interaction (e.g. liberating a Shelter). Cached per
## event scene path, since the catalog is authored on the scene and never changes.
var _interaction_value_cache: Dictionary = {}

func interaction_spawn_value(interaction: Interaction) -> float:
	if interaction == null or interaction.event == null:
		return 0.0
	var key: String = interaction.event.resource_path
	if _interaction_value_cache.has(key):
		return _interaction_value_cache[key]
	var value: float = _compute_interaction_spawn_value(interaction.event)
	_interaction_value_cache[key] = value
	return value


func _compute_interaction_spawn_value(event_scene: PackedScene) -> float:
	var root: Node = event_scene.instantiate()
	var spawners: Array = []
	if root is EventSpawnEntities:
		spawners.append(root)
	spawners.append_array(root.find_children("*", "EventSpawnEntities", true, false))
	var value: float = 0.0
	for spawner: EventSpawnEntities in spawners:
		for packed: PackedScene in spawner.entity_scenes:
			value += float(_scene_unit_cost(packed) * spawner.count)
	root.free()
	return value


## Ore cost of the unit a PackedScene spawns, via the tech tree (same convention as
## army_resource_value). Instantiates out of tree only to read the scene's piece id,
## then frees it. 0 when the scene isn't an Entity or the id isn't priced.
func _scene_unit_cost(packed: PackedScene) -> int:
	if packed == null:
		return 0
	var inst: Node = packed.instantiate()
	var t: StringName = inst.id if inst is Entity else &""
	inst.free()
	return unit_cost(t)


# ─── TECHNOLOGY / BUILD ORDER ───────────────────────────────────────────────

## The build/train preview instance for [type], or null when no tool produces it
## (e.g. an ability type). Lets the bot classify a catalog type by its SCENE's
## components instead of by the Entity.Type value. Reuses Commander's cached,
## out-of-tree preview instances.
func _preview_for_type(type) -> Node:
	var tool: Tool = Tool.for_type(type)
	return get_build_preview_instance(tool) if tool != null else null

## True when [type] builds a structure — detected by a "Structure" component on
## its preview scene rather than by reading the Entity.Type value.
func _type_is_structure(type) -> bool:
	var preview := _preview_for_type(type)
	return preview != null and preview.has_node("Structure")

## True when [type] trains a mobile unit — a producible scene with no "Structure"
## component. Excludes ability types (no producing tool, so no preview).
func _type_is_unit(type) -> bool:
	var preview := _preview_for_type(type)
	return preview != null and not preview.has_node("Structure")


## True when [type] is a COMBAT unit — its scene carries a Loadout with at least one
## Weapon. A unit with an empty Loadout (e.g. the colonial Stock Truck, whose utility
## role isn't wired yet) can't attack, so it returns false: the bot won't field it in
## attack waves or train it as army. Inspected on the cached build preview, so no
## per-type table is needed.
func unit_can_attack(type) -> bool:
	var preview := _preview_for_type(type)
	if preview == null:
		return false
	var loadout := preview.get_node_or_null("Loadout") as Loadout
	return loadout != null and loadout.has_weapons()


## True when [type] is a non-combat UTILITY unit worth fielding anyway — it can build
## structures (Builds) or perform interactions (Interactor), e.g. the Colonial Stock
## Truck. Lets production stand up a controlled number of these even though they can't
## attack. Inspected on the cached build preview, so no per-type table is needed.
func unit_is_utility(type) -> bool:
	var preview := _preview_for_type(type)
	if preview == null:
		return false
	return preview.has_node("Builds") or preview.has_node("Interactor")


## True when [type]'s scene carries the named component (e.g. "Production",
## "OreExtractor") — inspected on the cached build preview, so classification
## generalises without a per-type table.
func _type_has_component(type, component: String) -> bool:
	var preview := _preview_for_type(type)
	return preview != null and preview.has_node(component)


## Union of every Builds.buildable_types across the bot's owned units — the full
## set of structure types SOME builder it owns is allowed to place (a Set:
## type -> true). Empty when the bot owns no builder.
func _builder_buildable_types() -> Dictionary:
	var caps: Dictionary = {}
	for u: Commandable in _owned_units():
		var builds: Node = u.get_node_or_null("Builds")
		if builds != null:
			for t: StringName in builds.buildable_types:
				caps[t] = true
	return caps


## Every structure type the bot can currently place: it's in the build registry,
## SOME owned builder may build it, and its tech prerequisites are met (cost is the
## caller's concern). Derived from the registry + builder capabilities, so a newly
## added buildable structure is picked up automatically — no hardcoded type list.
func buildable_structure_types() -> Array:
	var caps := _builder_buildable_types()
	return Tool.tools_in_context(ControlBinding.ControlContext.BUILD).map(
		func(t: Tool): return t.type
	).filter(
		func(type): return caps.has(type) and has_tech_for(type)
	)


## Buildable structures that train units (carry a Production component) — the
## throughput buildings the economy expands (Redoubt, Hangar, …).
func buildable_production_structure_types() -> Array:
	return buildable_structure_types().filter(
		func(t): return _type_has_component(t, "Production")
	)


## Buildable structures that generate ore income (carry an OreExtractor — i.e.
## deposit-overlay mines).
func buildable_income_structure_types() -> Array:
	return buildable_structure_types().filter(
		func(t): return _type_has_component(t, "OreExtractor")
	)


## Buildable structures that generate dominion (carry a DominionGenerator — e.g. the
## Colonial internment camp). The generic hook the economy uses to stand up whatever
## structure a faction's dominion strategy needs, with no per-faction type list.
func buildable_dominion_structure_types() -> Array:
	return buildable_structure_types().filter(
		func(t): return _type_has_component(t, "DominionGenerator")
	)


## Buildable structures that supply vigor (their preview's vigor_provided > 0 — e.g.
## the Colonial power plant, Anarchical safehouse, Technocratic dwelling). The generic
## hook the economy uses to keep the commander out of vigor strain; the right
## faction-specific provider falls out of each faction's buildable set automatically.
func buildable_vigor_structure_types() -> Array:
	return buildable_structure_types().filter(func(t): return _type_provides_vigor(t))


## True when [type]'s build preview contributes vigor capacity (vigor_provided > 0),
## inspected on the cached preview so no per-type table is needed.
func _type_provides_vigor(type) -> bool:
	var preview := _preview_for_type(type)
	return preview is Commandable and (preview as Commandable).vigor_provided > 0


# ─── COUNTER-INTEL ──────────────────────────────────────────────────────────
# The fog-limited perception surface (visible_enemies, has_vision_at, vision_radius,
# get_enemies_near, seconds_elapsed) now lives on Commander, shared with players.

## How good a unit of [unit_type]'s MATCHUP is against [target]: the damage-table
## multiplier (effective_damage / base_damage, after armour + attributes) of the
## weapon it would use. 1.0 = neutral, >1 strong vs this target, <1 weak, and 0 when
## it can't hit the target at all (e.g. a ground-only weapon vs a flier). The
## multiplier — not absolute damage — so counter-selection keys off the matchup
## rather than which unit hits hardest (robust while raw damage is uncalibrated), and
## mirrors the targeting effectiveness signal. Reads the weapon off the cached train
## preview, so it generalises to any unit type with no per-type table.
func unit_effectiveness_vs(unit_type, target: Commandable) -> float:
	# A hand-set matchup override wins over the computed multiplier (AOE, kiting, …
	# the damage table can't express — e.g. Kamikaze ≫ Irregular).
	var override: Variant = DamageTable.matchup_override(unit_type, target.id)
	if override != null:
		return override
	# `target` must be a LIVE instance: targetable_layers()/armour come from runtime
	# nodes (target_body), so a build PREVIEW would read 0 and break this. Effectiveness
	# is otherwise type-level, so any live instance of a type is representative.
	var my_preview := _preview_for_type(unit_type)
	if my_preview == null:
		return 0.0
	var loadout := my_preview.get_node_or_null("Loadout") as Loadout
	if loadout == null:
		return 0.0
	var w: Weapon = loadout.weapon_for_target(target)
	if w == null:
		return 0.0
	var base: float = w.per_shot_damage()
	if base <= 0.0:
		return 0.0
	return DamageTable.calculate_damage(base, w.per_shot_damage_type(), target) / base


# ─── ARMY COMPOSITION (effectiveness-driven counter-production) ──────────────

## How much less we value covering structures than enemy units — beating the enemy
## ARMY is the immediate goal; razing structures (warlords' job) is the longer game.
const STRUCTURE_IMPORTANCE: float = 0.4

## Per believed enemy TYPE: { type -> { "demand": float, "rep": Commandable } }.
## demand = that type's summed importance across the believed-and-still-alive enemy
## comp (units 1.0, structures STRUCTURE_IMPORTANCE), DIVIDED DOWN by how well our
## current army already counters it — so a covered type has low demand (diminishing
## returns) and an unmet threat has high demand. `rep` is one live instance of the
## type, since effectiveness needs a live target (build previews read 0). Fog-limited:
## reads the blackboard's beliefs, restricted to entries whose entity is still alive.
func enemy_demand_map() -> Dictionary:
	if blackboard == null:
		return {}
	var importance: Dictionary = {}      # type -> summed importance
	var reps: Dictionary = {}            # type -> a live Commandable of that type
	for entry: CommanderBlackboard.Entry in blackboard.believed():
		if not is_instance_valid(entry.entity):
			continue
		var imp: float = STRUCTURE_IMPORTANCE if entry.is_structure else 1.0
		importance[entry.type] = importance.get(entry.type, 0.0) + imp
		if not reps.has(entry.type):
			reps[entry.type] = entry.entity

	# The enemy ALWAYS has a base to raze (the win condition), so guarantee a baseline
	# anti-structure target even when none is currently in view. Without this, a bot
	# that sees no enemy at all has zero demand and falls back to spamming the cheapest
	# unit — exactly the "keeps making irregulars" bug. Proxy the enemy's (unseen)
	# structures with one of our own (same armour class, a sound default otherwise).
	var sees_enemy_structure: bool = reps.values().any(
		func(r: Commandable): return r.has_node("Structure")
	)
	if not sees_enemy_structure:
		var own_structs := _owned_structures()
		if not own_structs.is_empty():
			var s_rep: Commandable = own_structs[0]
			importance[s_rep.id] = importance.get(s_rep.id, 0.0) + STRUCTURE_IMPORTANCE
			reps[s_rep.id] = s_rep

	var own := _owned_units()
	var demand: Dictionary = {}
	for etype in importance:
		var rep: Commandable = reps[etype]
		var coverage: float = 0.0
		for u: Commandable in own:
			coverage += unit_effectiveness_vs(u.id, rep)
		demand[etype] = {"demand": importance[etype] / (1.0 + coverage), "rep": rep}
	return demand


## How valuable building one more [unit_type] is against the current demand map: its
## effectiveness vs each believed enemy type (using that type's live rep) × its demand.
func unit_composition_value(unit_type, demand: Dictionary) -> float:
	var total: float = 0.0
	for etype in demand:
		var d: Dictionary = demand[etype]
		total += unit_effectiveness_vs(unit_type, d["rep"]) * d["demand"]
	return total


# ─── AOE-SUICIDE UNITS (kamikaze cost-effectiveness) ────────────────────────

## Ore cost of a type, from the tech tree.
func unit_cost(unit_type) -> int:
	var spec: TechnologySpec = technology_mapping.get(unit_type)
	return spec.ore_cost if spec != null else 0


## Total ore value of the enemy's army AS THE BOT BELIEVES IT — sum of the build cost
## of every believed-and-still-alive enemy UNIT on the blackboard (fog-limited: only
## units the bot has seen). The contextual aggression compares this against its own
## army value to decide whether it's ahead. 0 when nothing is believed.
func believed_enemy_army_value() -> float:
	if blackboard == null:
		return 0.0
	var total: float = 0.0
	for entry: CommanderBlackboard.Entry in blackboard.believed():
		if entry.is_structure or not is_instance_valid(entry.entity):
			continue
		total += unit_cost(entry.type)
	return total

## Cached per type: { "radius": float, "damage": float, "type": Damage.Type } when a
## unit is an AOE-SUICIDE unit (its weapon fires a projectile carrying a
## SuicideStatusEffect with a blast shape), else null. Detected from the projectile,
## not a unit name, so any such unit qualifies. Reads the projectile's HitShape
## sphere for the blast radius and its base_damage/damage_type.
var _aoe_profile_cache: Dictionary = {}

func aoe_suicide_profile(unit_type) -> Variant:
	if _aoe_profile_cache.has(unit_type):
		return _aoe_profile_cache[unit_type]
	var profile: Variant = _compute_aoe_suicide_profile(unit_type)
	_aoe_profile_cache[unit_type] = profile
	return profile

func _compute_aoe_suicide_profile(unit_type) -> Variant:
	var unit_preview := _preview_for_type(unit_type)
	if unit_preview == null:
		return null
	var loadout := unit_preview.get_node_or_null("Loadout") as Loadout
	if loadout == null:
		return null
	for w: Weapon in loadout.get_weapons():
		if w.projectile_scene == null:
			continue
		var proj: Node = w.projectile_scene.instantiate()
		var suicide: bool = not proj.find_children("*", "SuicideStatusEffect", true, false).is_empty()
		var radius: float = _projectile_blast_radius(proj)
		var dmg: Variant = proj.get("base_damage")
		var dtype: Variant = proj.get("damage_type")
		proj.free()
		if suicide and radius > 0.0 and dmg != null:
			return {"radius": radius, "damage": float(dmg), "type": dtype}
	return null

func _projectile_blast_radius(proj: Node) -> float:
	var hit := proj.get_node_or_null("HitShape") as CollisionShape3D
	if hit == null or not (hit.shape is SphereShape3D):
		return 0.0
	# Out-of-tree, so use local transforms: blast radius scales with the projectile
	# root and the shape node's own X scale.
	return (hit.shape as SphereShape3D).radius * (proj as Node3D).scale.x * hit.transform.basis.x.length()


## True when [unit] is an AOE-suicide unit (has an aoe_suicide_profile).
func is_suicide_aoe_unit(unit: Commandable) -> bool:
	return aoe_suicide_profile(unit.id) != null

## Owned AOE-suicide units (the ones BotKamikaze micromanages).
func get_suicide_aoe_units() -> Array:
	return _owned_units().filter(func(u: Commandable): return is_suicide_aoe_unit(u))


## The most COST-EFFECTIVE blast target for [kamikaze], or null if none clears the
## bar. For each visible enemy unit (a blast centre), the hit's value is summed over
## the enemy units the blast would catch: (HP-fraction it removes) × (their ore cost).
## A run is worth it only when that value beats the drone's own cost — i.e. the blast
## destroys more than it spends. Returns { "target": Commandable, "value": float }.
func kamikaze_best_target(kamikaze: Commandable) -> Variant:
	var profile: Variant = aoe_suicide_profile(kamikaze.id)
	if profile == null:
		return null
	var enemies := visible_enemies()
	var best_target: Commandable = null
	var best_value: float = 0.0
	for e: Commandable in enemies:
		if e.has_node("Structure"):
			continue  # centre blasts on enemy UNITS (clusters), not buildings
		var value: float = _aoe_hit_value(e.global_position, profile, enemies)
		if value > best_value:
			best_value = value
			best_target = e
	if best_target != null and best_value >= float(unit_cost(kamikaze.id)):
		return {"target": best_target, "value": best_value}
	return null

func _aoe_hit_value(center: Vector3, profile: Dictionary, enemies: Array) -> float:
	var c: Vector2 = VU.inXZ(center)
	var radius: float = profile["radius"]
	var total: float = 0.0
	for u: Commandable in enemies:
		if u.has_node("Structure") or u.defense == null or u.defense.hp_max <= 0.0:
			continue
		if c.distance_to(VU.inXZ(u.global_position)) > radius:
			continue
		var eff: float = DamageTable.calculate_damage(profile["damage"], profile["type"], u)
		var fraction: float = minf(eff, u.defense.hp) / u.defense.hp_max
		total += fraction * float(unit_cost(u.id))
	return total


## True when all prerequisite structures for [type] have been built,
## regardless of whether we can currently afford to produce it.
func has_tech_for(type: StringName) -> bool:
	var spec: TechnologySpec = technology_mapping.get(type)
	return spec != null and spec.unmet_need == TechnologySpec.UnmetNeed.NONE


## All Entity.Types whose prerequisite structures are satisfied — the full
## set of things we are currently able to build or train, ignoring cost.
func unlocked_types() -> Array:
	# Piece ids only — the map also carries int Ability.Type gate keys.
	return technology_mapping.keys().filter(
		func(t): return t is StringName and has_tech_for(t)
	)


## Structure types whose tech prerequisite is NOT yet met — each one
## represents a potential tech-tree expansion the bot could invest in.
func locked_structure_types() -> Array:
	return technology_mapping.keys().filter(
		func(t): return t is StringName and _type_is_structure(t) and not has_tech_for(t)
	)


## The most advanced unit type currently unlocked for training. Unit-vs-structure
## is decided by the type's scene (no "Structure" component); "most advanced"
## ranks by ore cost (ids are strings now, so the old enum-value ordering is
## gone — cost is the tech catalog's de-facto advancement axis), with the id as
## a deterministic tiebreak. Returns &"" when no units are available yet.
func highest_unlocked_unit_type() -> StringName:
	var unit_types := unlocked_types().filter(
		func(t): return _type_is_unit(t)
	)
	if unit_types.is_empty():
		return &""
	unit_types.sort_custom(func(a, b) -> bool:
		if unit_cost(a) != unit_cost(b):
			return unit_cost(a) < unit_cost(b)
		return String(a) < String(b)
	)
	return unit_types.back()


# ─── GAME PHASE / TIME ──────────────────────────────────────────────────────
# seconds_elapsed() now lives on Commander (shared perception surface).

## Coarse game-phase index: 0 = early, 1 = mid, 2 = late.
## Driven primarily by the number of distinct structure types owned
## (a proxy for tech-tree depth), with elapsed time as a backstop so
## the bot can't stay "early" indefinitely when base-building is slow.
func game_phase() -> int:
	# Distinct KINDS of built structure, keyed by scene rather than Entity.Type — a
	# proxy for tech-tree depth. Only fully-built structures count; one under
	# construction doesn't yet contribute tech or production capacity.
	var kinds: Dictionary = {}
	for s: Commandable in _owned_structures():
		if s.is_built:
			kinds[s.scene_file_path] = true
	var unique_struct_types := kinds.size()

	var elapsed := seconds_elapsed()
	if unique_struct_types >= 4 or elapsed > 180.0:
		return 2  # late
	elif unique_struct_types >= 2 or elapsed > 60.0:
		return 1  # mid
	return 0  # early
