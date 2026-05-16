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

func _owned_units() -> Array:
	return _owned_commandables().filter(
		func(c: Commandable): return c.is_in_group("unit")
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


## The number of owned Mines.  Serves as a relative income index — the
## actual per-tick ore yield is not yet tracked, so callers treat this as
## "how many income sources do we have" rather than ore-per-second.
func mine_count() -> int:
	return structure_type_map[Entity.Type.STRUCTURE_MINE].size()


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


## All units of a specific type (e.g. only Vanguards, only Sentries).
func get_units_of_type(type: Entity.Type) -> Array:
	return _owned_units().filter(func(c: Commandable): return c.type == type)


## All structures of a specific type.  Wraps structure_type_map for
## convenience so callers don't need to call .get_values() themselves.
func get_structures_of_type(type: Entity.Type) -> Array:
	return structure_type_map[type].get_values()


## Structures that have a Production component, meaning they can train units
## or run a build queue.
func get_production_structures() -> Array:
	var result: Array = []
	for t in Entity.Type.values():
		for s: Commandable in get_structures_of_type(t):
			if s.production != null:
				result.append(s)
	return result


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


## Maps Entity.Type → unit count for each type the bot owns.
## Use this to gauge army composition and spot imbalances
## (e.g. too many Technicians, zero Sentries).
func army_type_counts() -> Dictionary:
	var counts: Dictionary = {}
	for c: Commandable in _owned_units():
		counts[c.type] = counts.get(c.type, 0) + 1
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
		total += c.hp / c.hpMax
	return total / float(units.size())


## Rough combat-power score: sum of (DAMAGE × HP-fraction) for all owned
## units.  Captures both quantity and health state in a single number.
## Intended for relative comparisons (e.g. vs. estimate_enemy_strength()),
## not as an absolute damage-per-second figure.
func estimate_army_strength() -> float:
	var strength := 0.0
	for c: Commandable in _owned_units():
		strength += c.DAMAGE * (c.hp / c.hpMax)
	return strength


# ─── THREAT ASSESSMENT ──────────────────────────────────────────────────────

## All commandables (units and structures) belonging to enemy commanders.
func get_all_enemies() -> Array:
	return _commandables_of(_enemy_commanders())


## Only the mobile units owned by enemy commanders — the things that attack.
func get_enemy_units() -> Array:
	return get_all_enemies().filter(
		func(c: Commandable): return c.is_in_group("unit")
	)


## Only the structures owned by enemy commanders — the things to destroy.
func get_enemy_structures() -> Array:
	return get_all_enemies().filter(
		func(c: Commandable): return c.is_in_group("structure")
	)


## All enemy entities within [radius] world units of [position].
## Useful for hotspot checks: "how many enemies are near my Mine right now?"
func get_enemies_near(position: Vector3, radius: float) -> Array:
	if map == null:
		return []
	return SU.get_nearby_entities(
		map.get_world_3d(), position, radius, Map.CollisionMask.UNITS
	).filter(
		func(e): return e is Commandable and e.commander_id != id and e.commander_id != 0
	)


## Enemy units within [threat_radius] world units of any owned structure.
## Non-empty means the base is being actively pressured.  Deduplicates
## enemies that are close to several structures at once.
func get_enemies_threatening_base(threat_radius: float = 30.0) -> Array:
	if map == null:
		return []
	var seen: Dictionary = {}
	var threats: Array = []
	for t in Entity.Type.values():
		for s: Commandable in get_structures_of_type(t):
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
	for t in Entity.Type.values():
		for s: Commandable in get_structures_of_type(t):
			if not get_enemies_near(s.global_position, threat_radius).is_empty():
				var frac := s.hp / s.hpMax
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
		enemy_strength += c.DAMAGE * (c.hp / c.hpMax)
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
func base_centroid() -> Vector3:
	var all_s: Array = []
	for t in Entity.Type.values():
		all_s.append_array(get_structures_of_type(t))
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
	return neutral.get_children().filter(
		func(n): return n is Commandable and n.type == Entity.Type.STRUCTURE_MINE
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

## True when all prerequisite structures for [type] have been built,
## regardless of whether we can currently afford to produce it.
func has_tech_for(type: Entity.Type) -> bool:
	var spec: TechnologySpec = technology_mapping.get(type)
	return spec != null and spec.available


## All Entity.Types whose prerequisite structures are satisfied — the full
## set of things we are currently able to build or train, ignoring cost.
func unlocked_types() -> Array:
	return technology_mapping.keys().filter(func(t): return has_tech_for(t))


## Structure types whose tech prerequisite is NOT yet met — each one
## represents a potential tech-tree expansion the bot could invest in.
func locked_structure_types() -> Array:
	return technology_mapping.keys().filter(
		func(t: Entity.Type):
			# Structure types occupy the 0x1200..0x12FF range per Entity.Type.
			return (t & 0xFF00) == 0x1200 and not has_tech_for(t)
	)


## The most advanced unit type (highest Entity.Type value) currently
## unlocked for training.  Higher values map to later-tier units per the
## hex-encoded naming convention.  Returns UNDEFINED when no units are
## available yet.
func highest_unlocked_unit_type() -> Entity.Type:
	# Unit types occupy the 0x1100..0x11FF range.
	var unit_types := unlocked_types().filter(
		func(t: Entity.Type): return (t & 0xFF00) == 0x1100
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
	var unique_struct_types := 0
	for t in Entity.Type.values():
		if not get_structures_of_type(t).is_empty():
			unique_struct_types += 1

	var elapsed := seconds_elapsed()
	if unique_struct_types >= 4 or elapsed > 180.0:
		return 2  # late
	elif unique_struct_types >= 2 or elapsed > 60.0:
		return 1  # mid
	return 0  # early
