class_name Bot
extends Commander

## Bot — perception layer for a CPU-controlled commander.
##
## This script is a pure observation module: it exposes read-only query
## functions (the "senses") that a future AI strategy layer will call to
## understand game state before deciding what to do.  No decision-making
## or command-issuing logic belongs here.
##
## Scene placement: Bot expects to live at Scenario/Players/<bot>, which
## lets _ready() auto-resolve [map] and [scenario] by walking up the tree.
## Alternatively, call [method initialize] before any queries run to inject
## the references explicitly — useful if the tree structure ever changes.

## Reference to the game map, required for all spatial queries.
var map: Map

## Reference to the root scenario, required for frame-based timing and
## for locating enemy commanders.
var scenario: Scenario

## Persistent, fog-limited belief about the enemy (assigned + ticked by BotBrain).
## Composition decisions read believed enemy types from here so they survive vision
## flicker. Null until the brain wires it.
var blackboard: BotBlackboard


# ─── LIFECYCLE ──────────────────────────────────────────────────────────────

func _ready() -> void:
	super()
	# Auto-resolve from the expected position Scenario/Players/<bot>.
	# Scenario._ready() places all commanders under a "Players" Node3D that
	# is a direct child of Scenario, so two get_parent() calls suffice.
	var players := get_parent()
	if players != null and scenario == null:
		scenario = players.get_parent() as Scenario
	if scenario != null and map == null:
		map = scenario.map


## Explicit injection alternative to the tree-walk in _ready().
## Scenario._ready() can call this after adding the Bot as a child if it
## ever needs to wire references before any _ready() callbacks fire.
func initialize(a_map: Map, a_scenario: Scenario) -> void:
	map = a_map
	scenario = a_scenario


# ─── INTERNAL HELPERS ───────────────────────────────────────────────────────

# Entity.initialize() calls commander.add_child(entity), so every owned
# entity is a direct child of this node.  get_children() is therefore the
# authoritative source for owned-entity queries, and requires no scene-tree
# scan.
func _owned_commandables() -> Array:
	return get_children().filter(func(n): return n is Commandable)

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

# Gathers all commandables owned by an arbitrary list of commanders using
# the same child-based convention.
func _commandables_of(commanders: Array) -> Array:
	var result: Array = []
	for c: Commander in commanders:
		for child in c.get_children():
			if child is Commandable:
				result.append(child)
	return result

# Every Commander with id != 0 (neutral) and id != self.id is an enemy.
func _enemy_commanders() -> Array:
	if scenario == null:
		return []
	return scenario.commanders.filter(
		func(c: Commander): return c.id != id and c.id != 0
	)


# ─── ECONOMY ────────────────────────────────────────────────────────────────

## True when ore reserves are at or above [threshold].
## Use this to gate build decisions: "only expand if ore_is_above(400)".
func ore_is_above(threshold: int) -> bool:
	return ore >= threshold


## True when 80 % or more of population capacity is already consumed.
## A strained population will block the next unit train order; the bot
## should queue a Dwelling before training more units.
func population_is_strained() -> bool:
	return population_max > 0 and float(population_used) / float(population_max) >= 0.8


## The number of owned Mines that are fully built.  Serves as a relative income
## index — partially-built mines are excluded because they don't yet extract ore.
func mine_count() -> int:
	# A mine is a built structure that extracts ore — identified by its OreExtractor
	# component rather than by Entity.Type.
	return _owned_structures().filter(
		func(s: Commandable): return s.has_node("OreExtractor") and s.is_built
	).size()


## True when the bot has both the prerequisite tech unlock AND enough ore /
## population / dominion to produce [type] right now.
func can_afford(type: Entity.Type) -> bool:
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
func get_units_of_type(type: Entity.Type) -> Array:
	var scene_path := _scene_path_for_type(type)
	if scene_path == "":
		return []
	return _owned_units().filter(func(c: Commandable): return c.scene_file_path == scene_path)


## All structures of a specific type.  Wraps structure_type_map for
## convenience so callers don't need to call .get_values() themselves.
func get_structures_of_type(type: Entity.Type) -> Array:
	return structure_type_map[type].get_values()


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
		var spec: TechnologySpec = technology_mapping.get(u.type)
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


## All enemy entities within [radius] world units of [position].
## Useful for hotspot checks: "how many enemies are near my Mine right now?"
func get_enemies_near(position: Vector3, radius: float) -> Array:
	if map == null:
		return []
	return SU.get_nearby_entities(
		map.get_world_3d(), position, radius, CollisionLayers.TARGETABLE_ANY
	).filter(
		func(e): return e is Commandable and e.commander_id != id
	)


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
			for t: int in builds.buildable_types:
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


# ─── VISION (fog-limited perception) + COUNTER-INTEL ────────────────────────

## Enemy commandables the bot can currently SEE: those within the VisionRange of
## any owned unit or structure. The bot has no fog texture of its own (fog is the
## human's), so visibility is derived directly from owned entities' vision radii.
## Deduplicated. This is the fog-of-war boundary for the bot's decisions — they must
## not "cheat" by reading enemies the bot can't see.
func visible_enemies() -> Array:
	var result: Array = []
	var seen: Dictionary = {}
	for owned: Commandable in _owned_commandables():
		var vr: float = _shape_xz_radius(owned.vision_range_shape)
		if vr <= 0.0:
			continue
		for e in get_enemies_near(owned.global_position, vr):
			if not seen.has(e):
				seen[e] = true
				result.append(e)
	return result


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
	var override: Variant = DamageTable.matchup_override(unit_type, target.type)
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
	for entry: BotBlackboard.Entry in blackboard.believed():
		if not is_instance_valid(entry.entity):
			continue
		var imp: float = STRUCTURE_IMPORTANCE if entry.is_structure else 1.0
		importance[entry.type] = importance.get(entry.type, 0.0) + imp
		if not reps.has(entry.type):
			reps[entry.type] = entry.entity

	var own := _owned_units()
	var demand: Dictionary = {}
	for etype in importance:
		var rep: Commandable = reps[etype]
		var coverage: float = 0.0
		for u: Commandable in own:
			coverage += unit_effectiveness_vs(u.type, rep)
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


## True when the bot currently has vision of [world_pos]: some owned unit or
## structure is within its VisionRange of that point. Lets the blackboard verify
## whether a believed-but-unseen structure is still there when units revisit.
func has_vision_at(world_pos: Vector3) -> bool:
	var p: Vector2 = VU.inXZ(world_pos)
	for owned: Commandable in _owned_commandables():
		var vr: float = _shape_xz_radius(owned.vision_range_shape)
		if vr > 0.0 and VU.inXZ(owned.global_position).distance_to(p) <= vr:
			return true
	return false


## XZ radius of a CollisionShape3D (cylinder/sphere radius × node X-scale), or 0.
func _shape_xz_radius(shape_node: CollisionShape3D) -> float:
	if shape_node == null:
		return 0.0
	var scale: float = shape_node.global_transform.basis.x.length()
	var shp: Shape3D = shape_node.shape
	if shp is CylinderShape3D:
		return (shp as CylinderShape3D).radius * scale
	if shp is SphereShape3D:
		return (shp as SphereShape3D).radius * scale
	return 0.0


## True when all prerequisite structures for [type] have been built,
## regardless of whether we can currently afford to produce it.
func has_tech_for(type: Entity.Type) -> bool:
	var spec: TechnologySpec = technology_mapping.get(type)
	return spec != null and spec.unmet_need == TechnologySpec.UnmetNeed.NONE


## All Entity.Types whose prerequisite structures are satisfied — the full
## set of things we are currently able to build or train, ignoring cost.
func unlocked_types() -> Array:
	return technology_mapping.keys().filter(func(t): return has_tech_for(t))


## Structure types whose tech prerequisite is NOT yet met — each one
## represents a potential tech-tree expansion the bot could invest in.
func locked_structure_types() -> Array:
	return technology_mapping.keys().filter(
		func(t): return _type_is_structure(t) and not has_tech_for(t)
	)


## The most advanced unit type (highest Entity.Type value) currently
## unlocked for training.  Unit-vs-structure is decided by the type's scene (no
## "Structure" component); "most advanced" still ranks by the enum value, which is
## the tech catalog's intended ordering.  Returns UNDEFINED when no units are
## available yet.
func highest_unlocked_unit_type() -> Entity.Type:
	var unit_types := unlocked_types().filter(
		func(t): return _type_is_unit(t)
	)
	if unit_types.is_empty():
		return Entity.Type.UNDEFINED
	unit_types.sort()
	return unit_types.back()


# ─── GAME PHASE / TIME ──────────────────────────────────────────────────────

## Seconds elapsed since the scenario started, derived from the physics
## frame counter (30 ticks per second).
func seconds_elapsed() -> float:
	if scenario == null:
		return 0.0
	return float(scenario.frame) / float(Engine.physics_ticks_per_second)


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
