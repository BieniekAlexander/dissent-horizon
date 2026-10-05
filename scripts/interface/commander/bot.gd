@tool
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

# ─── CONTROL ─────────────────────────────────────────────────────────────────


## The decision layer driving this commander, or null before Scenario has attached one.
func brain() -> BotBrain:
	return get_node_or_null("BotBrain") as BotBrain


## True while this commander's decisions are its bot's. Every slot's commander is a Bot; a
## human's has its brain switched off, and debug mode can hand a slot between the two (see
## gdd/systems/ux/ui/debug-mode.md §A bot for every slot).
func is_ai_controlled() -> bool:
	var the_brain: BotBrain = brain()
	return the_brain != null and the_brain.active


# ─── INTERNAL HELPERS ───────────────────────────────────────────────────────


# A structure carries a "Structure" component (declaring its grid footprint); a
# mobile unit does not. Presence of that child node — NOT the Entity.Type — is the
# bot's unit/structure discriminator, so new scenes classify correctly without any
# type-table edits.
func _owned_units() -> Array:
	return _owned_commandables().filter(func(c: Commandable): return not c.structure_is_active())


func _owned_structures() -> Array:
	return _owned_commandables().filter(func(c: Commandable): return c.structure_is_active())


# ─── ECONOMY ────────────────────────────────────────────────────────────────


## True when energy reserves are at or above [threshold].
## Use this to gate build decisions: "only expand if energy_is_above(400)".
func energy_is_above(a_threshold: int) -> bool:
	return energy >= a_threshold


## Infrastructure surplus below which the bot should stand up its faction infrastructure provider
## before expanding further — roughly one unit-producing structure's upkeep, so it
## builds power proactively rather than waiting until it's already strained.
const INFRASTRUCTURE_PROVIDER_MARGIN: int = 40


## True when the commander lacks the headroom to add another infrastructure-consuming
## structure — the cue for BotEconomy to build a infrastructure provider before more buildings.
func needs_infrastructure_provider() -> bool:
	return infrastructure < INFRASTRUCTURE_PROVIDER_MARGIN


## The number of owned Extractors that are fully built.  Serves as a relative income
## index — partially-built extractors are excluded because they don't yet extract energy.
func extractor_count() -> int:
	# An extractor is a built structure that extracts energy — identified by its EnergyExtractor
	# component rather than by Entity.Type.
	return (
		_owned_structures()
		. filter(func(s: Commandable): return s.has_node("EnergyExtractor") and s.is_built)
		. size()
	)


## True when the bot has both the prerequisite tech unlock AND enough energy /
## infrastructure / dominion to produce [type] right now.
func can_afford(a_type: StringName) -> bool:
	return has_resources_for(a_type)


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
func _scene_path_for_type(a_type) -> String:
	var tool: Tool = Tool.for_type(a_type)
	return tool.packed_scene.resource_path if tool != null and tool.packed_scene != null else ""


## All units of a specific type (e.g. only Vanguards, only Irregulars). Matches by
## the unit's source scene rather than by inspecting its Entity.Type.
func get_units_of_type(a_type: StringName) -> Array:
	var scene_path := _scene_path_for_type(a_type)
	if scene_path == "":
		return []
	return _owned_units().filter(func(c: Commandable): return c.scene_file_path == scene_path)


## All structures of a specific type.  Wraps structure_type_map for
## convenience so callers don't need to call .get_values() themselves.
func get_structures_of_type(a_type: StringName) -> Array:
	var s: Variant = structure_type_map.get(a_type)
	return s.get_values() if s != null else []


## Structures that have a Production component AND are fully built, meaning they
## can currently train units. Under-construction structures are excluded because
## production.tick() is gated on is_built and their queues won't advance.
func get_production_structures() -> Array:
	return _owned_structures().filter(
		func(s: Commandable):
			return s.production != null and s.production.trains_units() and s.is_built
	)


## Production-capable structures with nothing to do: an empty training queue AND no
## purchase queued against them on the commander's production queue. Each one represents
## wasted throughput that the bot should fill. The pending check matters because a
## purchase the bot can't afford yet sits in that queue rather than on the structure —
## without it the bot would re-order the same unit every tick while saving up.
func get_idle_production_structures() -> Array:
	return get_production_structures().filter(
		func(s: Commandable):
			return s.production.is_free() and production_queue.pending_count_for(s) == 0
	)


## Units with no active command — standing idle and available to be re-tasked.
func get_idle_units() -> Array:
	return _owned_units().filter(func(c: Commandable): return not c.has_command())


## Total number of units owned by this commander.
func army_size() -> int:
	return _owned_units().size()


## Total energy value of the owned army — sum of each unit's build cost (its
## technology_mapping energy_cost). Used by the military as the "how much have I
## invested in an army" gauge that drives attack-wave commitment.
func army_resource_value() -> float:
	var total: float = 0.0
	for u: Commandable in _owned_units():
		var spec: TechnologySpec = technology_mapping.get(u.id)
		if spec != null:
			total += spec.energy_cost
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
		strength += entity_strength(c)
	return strength


# ─── THREAT ASSESSMENT ──────────────────────────────────────────────────────


## All commandables (units and structures) belonging to enemy commanders.
func get_all_enemies() -> Array:
	return _commandables_of(_enemy_commanders())


## Only the mobile units owned by enemy commanders — the things that attack.
func get_enemy_units() -> Array:
	return get_all_enemies().filter(func(c: Commandable): return not c.structure_is_active())


## Only the structures owned by enemy commanders — the things to destroy.
func get_enemy_structures() -> Array:
	return get_all_enemies().filter(func(c: Commandable): return c.structure_is_active())


## Enemy commandables within [unit]'s aggro range, keeping only targets ranked at least
## as important as [min_target_priority] and sorting them by target priority (most
## important first). Uses the unit's actual aggro volumes via Entity.hostiles_in_aggro —
## the same check Commandable.get_aggro_near_position runs, including its vision gate: an
## enemy this bot cannot see (fogged or stealthed) is not in aggro range, so the bot does
## not react to what its units could not have picked a fight with. Empty when the unit has none.
func get_enemies_in_aggro_range(
	a_unit: Commandable,
	min_target_priority: Entity.TargetPriority = Entity.TargetPriority.NON_COMBAT_UNITS
) -> Array:
	var enemies: Array = a_unit.hostiles_in_aggro().filter(
		func(e):
			return (
				e is Commandable
				and e.commander_id != id
				and e.commander_id != 0
				and e.target_priority <= min_target_priority
				and e.is_visible_to(id)
			)
	)
	enemies.sort_custom(func(a: Entity, b: Entity): return a.target_priority < b.target_priority)
	return enemies


## Enemy units within [threat_radius] world units of any owned structure.
## Non-empty means the base is being actively pressured.  Deduplicates
## enemies that are close to several structures at once.
## NOTE: intentionally includes unbuilt structures — an enemy attacking a
## structure under construction is still a threat worth responding to.
func get_enemies_threatening_base(a_threat_radius: float = 30.0) -> Array:
	if map == null:
		return []
	var seen: Dictionary = {}
	var threats: Array = []
	for s: Commandable in _owned_structures():
		for enemy: Commandable in get_enemies_near(s.global_position, a_threat_radius):
			if not seen.has(enemy):
				seen[enemy] = true
				threats.append(enemy)
	return threats


## True when at least one enemy unit is within [threat_radius] of any
## owned structure.
func is_base_under_threat(a_threat_radius: float = 30.0) -> bool:
	return not get_enemies_threatening_base(a_threat_radius).is_empty()


## The owned structure most in danger: lowest HP fraction among those
## that currently have enemies nearby.  Returns null if nothing is under
## active attack.  A natural rally target for defensive units.
func most_threatened_structure(a_threat_radius: float = 30.0) -> Commandable:
	var worst: Commandable = null
	var worst_frac := 1.0
	for s: Commandable in _owned_structures():
		if not get_enemies_near(s.global_position, a_threat_radius).is_empty():
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
		enemy_strength += entity_strength(c)
	var own := estimate_army_strength()
	var total := own + enemy_strength
	if total == 0.0:
		return 0.0
	return enemy_strength / total


# ─── CLUSTERING ─────────────────────────────────────────────────────────────
#
# THE PERCEPTION PRIMITIVE BETWEEN "one unit" and "the whole army".
#
# Every other spatial sense here is either an aggregate (army_centroid,
# relative_threat_level) or a nearest-X lookup, and neither can express "the smaller of
# two threats" or "leave half at home" — which is why BotMilitary can only ever point
# everything at one position. Clustering was implemented three times before this section
# existed (CU.get_nodes_clustered, called only by a scenario event; BotSanction's densest
# scan; the kamikaze blast valuation) and shared none of it.
#
# TWO DIFFERENT QUESTIONS live here, and conflating them would break sanction aiming:
#   • GROUPING — "how many enemy forces are there, where, how strong" (enemy_clusters).
#   • COVERAGE — "where would a radius-R effect catch the most value" (best_covered_point).
# A group's centroid does NOT answer the coverage question: a long chain of units is one
# group whose centroid may sit within reach of none of them.

## How close two enemies must be to count as one force, in world units. Single-linkage, so
## this is a CHAIN distance: a line of units spaced under it reads as one group however
## long the line is. Sized to a small engagement's footprint rather than to any weapon.
const CLUSTER_LINK_DISTANCE: float = 8.0


## One believed enemy force — a group of enemies close enough to fight as one.
class EnemyCluster:
	var members: Array  ## Commandable
	var centroid: Vector3
	## Σ damage × hp fraction, the same measure relative_threat_level and
	## estimate_army_strength use, so the three are comparable.
	var strength: float
	## Σ build cost — what destroying this force is WORTH, in the energy-equivalent currency
	## the bot compares options in.
	var energy_value: float
	## Mean velocity of the members: where the force is heading, for reading an approach.
	var heading: Vector3

	func size() -> int:
		return members.size()


## Visible enemy UNITS grouped into forces, strongest first. Live entities rather than
## remembered ones, because every consumer so far acts on them (aiming, valuing a blast,
## picking an objective) and a remembered position cannot be aimed at.
##
## TODO: a believed_enemy_clusters() over the blackboard's last-known locations is the
## variant strategic planning wants — attacking a force you remember rather than one you
## can see. Not built; it needs the grouping to work on positions rather than on nodes.
func enemy_clusters(a_link_distance: float = CLUSTER_LINK_DISTANCE) -> Array:
	var units: Array = visible_enemies().filter(
		func(e: Commandable): return not e.structure_is_active()
	)
	var groups: Array = CU.get_nodes_clustered(units, a_link_distance)
	var out: Array = groups.map(func(g: Array): return _cluster_of(g))
	out.sort_custom(func(a: EnemyCluster, b: EnemyCluster): return a.strength > b.strength)
	return out


## CAPTURABLE PREY grouped into clusters — how many separate capture ERRANDS are live.
##
## The same grouping as enemy_clusters over a different set: the visible enemies a carrier
## may imprison, plus the loose neutral Terrestrials, which is exactly the candidate list
## BotOpportunist._gather_captures draws from. One CLUSTER rather than one prisoner is the
## unit of work because a truck holding three collects a whole knot of infantry on one trip,
## so counting bodies would size the fleet against the map's population rather than against
## the number of trips.
##
## Fog-limited through get_capturable_enemies; neutrals are world features the bot knows
## about regardless (see get_neutral_terrestrials), on the same footing as extraction sites.
func capturable_clusters(a_link_distance: float = CLUSTER_LINK_DISTANCE) -> Array:
	var prey: Array = get_capturable_enemies() + get_neutral_terrestrials()
	if prey.is_empty():
		return []
	var groups: Array = CU.get_nodes_clustered(prey, a_link_distance)
	return groups.map(func(g: Array): return _cluster_of(g))


## Summarise one group of enemies into the EnemyCluster the deciders read.
##
## Split into a geometry half and a valuation half because they answer to different things:
## a position only exists for a node in the scene tree, while strength and price are read
## off components and are true of an entity anywhere. Keeping them apart is also what makes
## each half testable on its own.
func _cluster_of(a_members: Array) -> EnemyCluster:
	var cluster := EnemyCluster.new()
	cluster.members = a_members
	cluster.centroid = centroid_of(a_members)
	var profile: Dictionary = _cluster_profile(a_members)
	cluster.strength = profile["strength"]
	cluster.energy_value = profile["energy_value"]
	cluster.heading = profile["heading"]
	return cluster


## Mean world position of any group of nodes; ZERO for an empty one.
static func centroid_of(a_nodes: Array) -> Vector3:
	if a_nodes.is_empty():
		return Vector3.ZERO
	var sum := Vector3.ZERO
	for n: Node3D in a_nodes:
		sum += n.global_position
	return sum / float(a_nodes.size())


## Everything about a group that is NOT geometry:
## { "strength": Σ damage × hp fraction, "energy_value": Σ build cost, "heading": mean
## velocity }. Heading is what reads an approach — a force moving toward the base is a
## different problem from the same force sitting still.
func _cluster_profile(a_members: Array) -> Dictionary:
	var strength: float = 0.0
	var energy_value: float = 0.0
	var velocity_sum := Vector3.ZERO
	for m: Commandable in a_members:
		velocity_sum += m.velocity
		strength += entity_strength(m)
		energy_value += float(unit_cost(m.id))
	var heading: Vector3 = (
		velocity_sum / float(a_members.size()) if not a_members.is_empty() else Vector3.ZERO
	)
	return {"strength": strength, "energy_value": energy_value, "heading": heading}


## One entity's contribution to a strength estimate: its damage output scaled by how much
## of it is left. The single definition of "how strong is this thing", so estimate_army_
## strength, relative_threat_level and a cluster's strength cannot drift apart.
func entity_strength(a_entity: Commandable) -> float:
	if a_entity.defense == null or a_entity.defense.hp_max <= 0.0:
		return 0.0
	var damage: float = (
		a_entity.weapon_inventory.total_damage() if a_entity.weapon_inventory != null else 0.0
	)
	return damage * (a_entity.defense.hp / a_entity.defense.hp_max)


## True when `a_unit` is ARMED — a Loadout that actually holds a Weapon. An empty Loadout is
## a node without weapons, so `weapon_inventory != null` is not this question.
func unit_is_armed(a_unit: Commandable) -> bool:
	return a_unit.weapon_inventory != null and a_unit.weapon_inventory.has_weapons()


## True when `a_unit` kills by DRIVING OVER things — the crush mechanic, which is a size-class
## comparison on Movement and needs no component of its own (Movement.can_crush_anything).
func unit_can_crush(a_unit: Commandable) -> bool:
	return a_unit.movement != null and a_unit.movement.can_crush_anything()


## WHETHER A UNIT CAN HURT THE ENEMY AT ALL — armed, or heavy enough to crush.
##
## "Unarmed" is not the same as "useless", and reading it that way is what left the Colonial
## Stock Truck accounted for as an idle body nobody wanted: it has an empty Loadout, so every
## armed-only test filtered it out of the army, out of the re-task and out of the idle sweep
## alike, and it stood still for the rest of the match (measured at 8-22 idle units per side
## before the engagement fixes, 3-7 after, rising monotonically in every match). The truck is
## in fact the piece that runs light infantry over — and on this content that crush IS the
## Colonial capture, so pointing it at the enemy army is productive rather than suicidal.
##
## Deliberately NOT the same question as BotScout._applicable_responsibility_count's "does
## the army want this unit": crushing is contact damage a unit does wherever it happens to
## be, not a job that keeps it somewhere, so it does not make a unit needed elsewhere.
func unit_has_combat_utility(a_unit: Commandable) -> bool:
	return unit_is_armed(a_unit) or unit_can_crush(a_unit)


## WHERE A RADIUS-`a_radius` EFFECT SHOULD LAND to catch the most of `a_candidates`.
##
## Centres the scan on each candidate in turn and totals `a_weight` over everything within
## the radius of it — so the answer is always a point some real entity sits at, which is
## what makes it reachable and aimable. `a_weight` is Callable(Commandable) -> float: pass
## one that returns 1.0 to count bodies, or a damage-and-price function to value a blast.
##
## Returns {"anchor": the candidate centred on (null when none), "center": centroid of what
## it catches, "members": those caught, "weight": their summed weight}.
func best_covered_point(a_candidates: Array, a_radius: float, a_weight: Callable) -> Dictionary:
	var best: Dictionary = {"anchor": null, "center": Vector3.ZERO, "members": [], "weight": 0.0}
	for candidate: Node3D in a_candidates:
		var centre: Vector2 = VU.in_xz(candidate.global_position)
		var caught: Array = a_candidates.filter(
			func(o: Node3D): return VU.in_xz(o.global_position).distance_to(centre) <= a_radius
		)
		var weight: float = 0.0
		for c in caught:
			weight += a_weight.call(c)
		if weight <= best["weight"]:
			continue
		var sum := Vector3.ZERO
		for c: Node3D in caught:
			sum += c.global_position
		best = {
			"anchor": candidate,
			"center": sum / float(caught.size()),
			"members": caught,
			"weight": weight,
		}
	return best


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


## How this scenario ends (Scenario.win_condition); MISSION for a bot with no scenario, as
## in a bare test. Under HEGEMONY the enemy's command centres are the objective and this
## bot's own are its first defensive priority (BotMilitary).
func win_condition() -> Scenario.WinCondition:
	return scenario.win_condition if scenario != null else Scenario.WinCondition.MISSION


func is_command_centre_type(a_type: StringName) -> bool:
	return Deployment.is_command_centre_id(a_type)


## The owned command centre with enemies within `a_threat_radius`, the most hurt first, or
## null. Asked at a wider radius than most_threatened_structure's: under HEGEMONY a centre
## is the whole game, so an enemy still some way off it is already a threat to it.
func threatened_command_centre(a_threat_radius: float) -> Commandable:
	var worst: Commandable = null
	var worst_frac: float = INF
	for s: Commandable in _owned_structures():
		if not Deployment.is_command_centre(s):
			continue
		if get_enemies_near(s.global_position, a_threat_radius).is_empty():
			continue
		var frac: float = s.defense.hp / s.defense.hp_max if s.defense != null else 0.0
		if frac < worst_frac:
			worst_frac = frac
			worst = s
	return worst


## A direction squared below this is "no direction" — the anchor sits on the target.
const DIRECTION_EPSILON: float = 1.0e-6


## WHICH WAY THE THREAT IS, as a unit vector on XZ from `a_from_xz`: toward the nearest enemy
## structure this bot has SEEN, else the nearest enemy unit it remembers, else the middle of
## the map — fog-limited, like the attack objective, so the bot orients against what it has
## found. One axis read by placement (production forward, support behind) and by the
## military (where the army stands), so the two cannot disagree about where "forward" is.
## The last fallback is the one line that names a world axis; it is reached only with the
## anchor exactly on the map centre and nothing believed.
func threat_direction(a_from_xz: Vector2) -> Vector2:
	var believed: Variant = nearest_believed_enemy_structure_position()
	if believed == null:
		believed = nearest_believed_enemy_unit_position(base_centroid())
	if believed != null:
		var to_threat: Vector2 = VU.in_xz(believed) - a_from_xz
		if to_threat.length_squared() > DIRECTION_EPSILON:
			return to_threat.normalized()
	if map != null:
		var to_centre: Vector2 = map.world_bounds().get_center() - a_from_xz
		if to_centre.length_squared() > DIRECTION_EPSILON:
			return to_centre.normalized()
	return Vector2(0.0, 1.0)


## The owned command centres — under HEGEMONY, the whole game, and so what a static defence
## stands in front of. Empty when none stands.
func owned_command_centres() -> Array:
	return _owned_structures().filter(
		func(s: Commandable) -> bool: return Deployment.is_command_centre(s)
	)


## The owned structure furthest ALONG `a_direction` from the base centroid — the building
## the enemy reaches first coming that way, and so the one the army stands in front of. Null
## when the bot owns no structure.
func frontmost_structure(a_direction: Vector2) -> Commandable:
	var origin: Vector2 = VU.in_xz(base_centroid())
	var best: Commandable = null
	var best_along: float = -INF
	for s: Commandable in _owned_structures():
		var along: float = (VU.in_xz(s.global_position) - origin).dot(a_direction)
		if along > best_along:
			best_along = along
			best = s
	return best


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


## Owned, fully-built structures that have an OCCUPIABLE Garrison with remaining space.
## Closed garrisons (see Garrison.is_closed) are excluded: no unit can be ordered into one,
## so they are holds, not shelter. Which units a remaining host will actually take is
## per-unit (Garrison.accepts) — see nearest_garrison_for.
func get_garrison_structures() -> Array:
	return _owned_structures().filter(
		func(s: Commandable) -> bool:
			return (
				s.is_built
				and s.garrison != null
				and not s.garrison.is_closed()
				and s.garrison.can_garrison()
			)
	)


## Bunkers this bot's units may be ordered INTO and fire out of: its own built, open bunker
## garrisons and the NEUTRAL ones. A neutral building adopts its first occupant's side
## (Garrison._adopt_commander_if_neutral) and is closed to the enemy from then on, so it is
## as good as owned — and it is where most of the cover on a map is. Whether a given unit
## is admitted is Garrison.accepts, asked by the caller.
func get_bunker_hosts() -> Array:
	var hosts: Array = get_garrison_structures().filter(
		func(s: Commandable) -> bool: return s.garrison.bunker
	)
	var neutral: Commander = _neutral_commander()
	if neutral == null:
		return hosts
	for node: Node in neutral.get_children():
		var s := node as Commandable
		if (
			s != null
			and s.structure_is_active()
			and s.is_built
			and s.garrison != null
			and s.garrison.bunker
			and not s.garrison.is_closed()
			and s.garrison.can_garrison()
		):
			hosts.append(s)
	return hosts


## Owned hosts holding at least one unit of this bot's that an order may let out — where the
## army's bunkered units are, for the wave to collect them.
func get_hosts_holding_my_units() -> Array:
	return _owned_structures().filter(
		func(s: Commandable) -> bool:
			return (
				s.garrison != null
				and s.garrison.occupants().any(
					func(u: Commandable) -> bool: return s.garrison.can_release_occupant(u)
				)
			)
	)


## Whether ground can WALK from `a_from` to within `a_tolerance` of `a_to` on the map's
## navigation mesh. False for ground across a cliff or walled in: an objective nobody can
## reach is a place the army would stand beside for ever. True when no navigation map is
## ready yet — unknown is not unreachable.
func is_reachable(a_from: Vector3, a_to: Vector3, a_tolerance: float) -> bool:
	if map == null or map.nav_region == null:
		return true
	var nav_map: RID = map.nav_region.get_navigation_map()
	if not nav_map.is_valid() or NavigationServer3D.map_get_iteration_id(nav_map) == 0:
		return true
	var path: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, a_from, a_to, true)
	if path.is_empty():
		return false
	return VU.in_xz(path[path.size() - 1]).distance_to(VU.in_xz(a_to)) <= a_tolerance


## The nearest owned garrison structure that would accept [unit], or null when the bot
## owns none. Used by preservation to garrison at-risk units — filtered by accepts() so
## a host whose occupancy masks reject this unit isn't offered as a refuge it can't reach.
func nearest_garrison_for(a_unit: Commandable) -> Commandable:
	var hosts: Array = get_garrison_structures().filter(
		func(s: Commandable) -> bool: return s.garrison.accepts(a_unit)
	)
	if hosts.is_empty():
		return null
	return (
		AU
		. sort_on_key(
			func(s: Commandable):
				return a_unit.global_position.distance_squared_to(s.global_position),
			hosts
		)
		. front()
	)


## The owned structure nearest to [from], or null when the bot owns none.
## Used by BotPreservation as the retreat waypoint for at-risk units.
func nearest_own_structure(a_from: Vector3) -> Commandable:
	var structs: Array = _owned_structures()
	if structs.is_empty():
		return null
	return (
		AU
		. sort_on_key(
			func(s: Commandable): return a_from.distance_squared_to(s.global_position), structs
		)
		. front()
	)


## The enemy structure closest to our base centroid.
## Attacking the nearest enemy building minimises exposure while applying
## economic pressure.  Returns null when no enemy structures exist.
##
## OMNISCIENT — it reads the live scene. That is fine for a query about what EXISTS (the
## hostile-target audit in tests/test_BotHostileTargets.gd uses it that way), but it is not
## what the army marches on any more: see nearest_believed_enemy_structure_position.
func nearest_enemy_structure_to_base() -> Commandable:
	var enemies := get_enemy_structures()
	if enemies.is_empty():
		return null
	var base := base_centroid()
	return (
		AU
		. sort_on_key(
			func(s: Commandable): return base.distance_squared_to(s.global_position), enemies
		)
		. front()
	)


# ─── THE ATTACK OBJECTIVE, FOG-LIMITED ──────────────────────────────────────
#
# WHERE THE ARMY MARCHES IS A BELIEF, NOT A FACT, and that is the whole point of this
# section. `nearest_enemy_structure_to_base` and `get_enemy_units` read the live scene, so
# the bot knew where the opponent had built from tick 0 and where every enemy unit stood
# right now, without ever having scouted anything. Two consequences, and the second is the
# one that mattered: a bot that had seen nothing still had a committed ATTACK objective
# (measured — `has_attack_objective` true from tick ~300 with `believed_enemy_army_value`
# still 0, gdd/systems/ai/bot-engagement-fixes.md), and `INFORMATION_VALUE_ENERGY` was
# buying far less than BotScout's trade-off claims, because the most valuable thing scouting
# could tell the bot was already free.
#
# Both queries below answer with a POSITION rather than a Commandable, and they have to: a
# belief outlives the thing it remembers (the blackboard drops a structure only when the
# commander regains vision of its spot and finds it gone), so "the last place I saw their
# base" is still somewhere worth marching on after the building has been destroyed. The walk
# is self-correcting — arriving grants vision, the revisit drops the belief, and the next
# think picks a different objective or falls back to MASS.


## Last-known location of the BELIEVED enemy structure nearest our base, or null when the
## bot has never seen one. THE ATTACK OBJECTIVE: no sighting, no offensive.
##
## `a_accept` is an optional Callable(CommanderBlackboard.Entry) -> bool: a belief it
## rejects is not an objective. See `_nearest_belief_position`.
func nearest_believed_enemy_structure_position(a_accept: Variant = null) -> Variant:
	return _nearest_belief_position(
		blackboard.believed_structures() if blackboard != null else [], base_centroid(), a_accept
	)


## The believed enemy structure nearest the base that `a_accept` admits, as its ENTRY rather
## than its position — for a caller that wants the remembered entity as well as where it
## was, such as the army ordering an Attack on the building it has reached.
func nearest_believed_enemy_structure_entry(a_accept: Variant = null) -> CommanderBlackboard.Entry:
	return _nearest_belief_entry(
		blackboard.believed_structures() if blackboard != null else [], base_centroid(), a_accept
	)


## Last-known location of the BELIEVED enemy unit nearest `a_from`, or null when none is
## remembered. What the army goes after once the opponent has no structures left standing —
## unit beliefs lapse (CommanderBlackboard.BLACKBOARD_EXPIRATION), so this fades rather than
## pointing at a stale ghost forever.
func nearest_believed_enemy_unit_position(a_from: Vector3, a_accept: Variant = null) -> Variant:
	return _nearest_belief_position(
		blackboard.believed_units() if blackboard != null else [], a_from, a_accept
	)


## The nearest of `a_entries`' last-known locations to `a_from`, or null for an empty set.
##
## `a_accept`, when given, is Callable(CommanderBlackboard.Entry) -> bool and filters the
## set BEFORE the nearest is taken — so a rejected belief does not merely lose, it is not a
## candidate, and the query answers with the nearest ACCEPTABLE belief rather than with
## nothing. That distinction is the whole point: the army must be able to skip the enemy
## scan drone parked at its gate and still march on the base behind it.
func _nearest_belief_position(
	a_entries: Array, a_from: Vector3, a_accept: Variant = null
) -> Variant:
	var best: CommanderBlackboard.Entry = _nearest_belief_entry(a_entries, a_from, a_accept)
	return best.last_known_location if best != null else null


## The entry behind _nearest_belief_position: the nearest acceptable belief itself, or null.
func _nearest_belief_entry(
	a_entries: Array, a_from: Vector3, a_accept: Variant
) -> CommanderBlackboard.Entry:
	var accept: Callable = a_accept if a_accept is Callable else Callable()
	var best: CommanderBlackboard.Entry = null
	var best_dist_sq: float = INF
	for entry: CommanderBlackboard.Entry in a_entries:
		if accept.is_valid() and not accept.call(entry):
			continue
		var dist_sq: float = a_from.distance_squared_to(entry.last_known_location)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best = entry
	return best


# ─── CAN WE ACTUALLY HURT IT? ────────────────────────────────────────────────
#
# THE QUESTION NEITHER OBJECTIVE SELECTION NOR THE KAMIKAZE SCAN USED TO ASK. Aggro
# (`Commandable.get_aggro_near_position`) and `BotTargeting._retarget` both filter their
# candidates through `Loadout.weapon_for_target`, so the capability was always there — it
# simply was not consulted anywhere a bot decides WHERE TO GO or WHAT TO COMMIT TO. The
# reported symptom is what that costs: an army ordered onto a Scan drone marches out,
# arrives, and stands, and a suicide drone handed one holds a `persist = true` Attack it can
# never act on until the drone's lifespan runs out.
#
# `weapon_for_target` is the honest form of the question. A weapon may fire on a target iff
# its `target_mask` intersects that target's TARGETABLE_GROUND / TARGETABLE_AIR layers
# (`Weapon.can_target`), so "no weapon can lock onto this at all" is a different fact from
# "the matchup multiplier is 0" — `unit_effectiveness_vs` answers 0 for BOTH, and a Scan
# drone is the first kind: a HOVERING piece on the air layer that a ground-only loadout has
# no targeting mode for. Counter-effectiveness (the damage matchup table) still decides who
# to BUILD and who to PREFER; this decides what is a legal thing to commit to at all.


## Can `a_unit` bring a WEAPON to bear on `a_target` — its own, or (as a bunker) a garrisoned
## occupant's? Exactly the pair of tests `Attack.meets_precondition` applies, asked before
## the order is issued rather than after, so it is also the honest bound on who may be handed
## an Attack at all.
static func unit_can_shoot(a_unit: Commandable, a_target: Commandable) -> bool:
	if a_unit == null or a_target == null:
		return false
	if a_unit.weapon_inventory != null and a_unit.weapon_inventory.any_weapon_can_target(a_target):
		return true
	return a_unit.garrison != null and a_unit.garrison.any_garrison_can_target(a_target)


## Can `a_unit` take HP off `a_target` by any means it has — shoot it, or DRIVE OVER IT?
##
## The crush half is not a flourish: `unit_has_combat_utility` already rules that an unarmed
## Stock Truck is an army member precisely because it runs light infantry over, so a
## weapon-only test here would judge an army of them unable to hurt anything and leave the
## bot with no objective at all. `Movement.can_crush` is the per-target form of the same
## size-class rule the engine crushes by, so this agrees with what would actually happen on
## contact — including its refusals: nothing crushes an AERIAL piece, so a truck still
## cannot answer a Scan drone.
##
## The weapon-only question survives as `unit_can_shoot` because the two are genuinely
## different: what may an army MARCH ON, versus who may be handed an Attack.
static func unit_can_damage(a_unit: Commandable, a_target: Commandable) -> bool:
	if unit_can_shoot(a_unit, a_target):
		return true
	return (
		a_unit != null
		and a_target != null
		and a_unit.movement != null
		and a_target.movement != null
		and a_unit.movement.can_crush(a_target.movement)
	)


## Can ANY of `a_units` damage `a_target`? The ARMY-level form: an objective no member of
## the army can hurt is not an objective.
##
## Answers TRUE for a target it cannot interrogate — one that has been freed, or is alive
## but out of the tree — because UNKNOWN IS NOT UNTARGETABLE. A belief outlives the thing it
## remembers, and refusing to march on a remembered position because the memory can no
## longer be questioned would forbid exactly the self-correcting walk the fog-limited
## objective is built on (see the section above `nearest_believed_enemy_structure_position`).
## An empty army answers true for the same reason: there is no one to ask.
##
## VALIDITY IS CHECKED BEFORE THE CAST, and that order is load-bearing: `freed as Commandable`
## is itself an engine error in Godot 4, and a belief whose remembered entity has been
## destroyed is the ordinary case here, not an edge one.
static func any_unit_can_damage(a_units: Array, a_target: Variant) -> bool:
	if a_target == null or not is_instance_valid(a_target):
		return true
	var target: Commandable = a_target as Commandable
	if target == null or not target.is_inside_tree():
		return true
	for u: Commandable in a_units:
		if unit_can_damage(u, target):
			return true
	return a_units.is_empty()


## Has this bot already DISPROVED `a_entry` by walking to it — i.e. does it have vision of
## the remembered spot, with the remembered unit no longer on it?
##
## Structures always answer false: `CommanderBlackboard.update` already drops a structure
## belief the moment the commander regains vision of its cell and finds it gone, so the
## question is asked and answered there. UNIT beliefs get no such rule — they lapse only on
## `BLACKBOARD_EXPIRATION`, three simulated minutes — so an army that marches on the last
## place it saw an enemy SCOUT arrives, looks straight at an empty patch of ground, and goes
## on believing in it. This is the missing half of the "the walk is self-correcting" claim
## the objective section above makes.
##
## Deliberately asked HERE, of the objective, rather than by erasing the entry: the belief is
## still evidence for `believed_enemy_army_value` and `enemy_demand_map` (that unit exists,
## and we saw it), it is only no longer evidence about WHERE. Whether the blackboard itself
## should drop it is raised as a question in gdd/systems/ai/bot-engagement-fixes.md.
func belief_is_disproved(a_entry: CommanderBlackboard.Entry) -> bool:
	if a_entry == null or a_entry.is_structure:
		return false
	# Asked of the raw field, and validity first: a destroyed entity is the ordinary case for
	# a belief, and casting or dereferencing a freed object is an engine error.
	var remembered: Variant = a_entry.entity
	if (
		is_instance_valid(remembered)
		and (remembered as Node).is_inside_tree()
		and (
			VU.in_xz((remembered as Node3D).global_position).distance_to(
				VU.in_xz(a_entry.last_known_location)
			)
			<= BELIEF_VERIFY_RADIUS
		)
	):
		return false  # it is still where we remember it
	return has_vision_at(a_entry.last_known_location)


## How far (world units) a remembered unit may have drifted from its last-known location and
## still count as "where we remember it". Sized to a unit's own footprint plus the slop of a
## navmesh-snapped arrival, so ordinary jostling in place is not read as the thing having
## left.
const BELIEF_VERIFY_RADIUS: float = 3.0


## Extractors still owned by the neutral commander (id == 0) — uncontested
## resource nodes worth sending a Technician to capture.
func get_neutral_extractors() -> Array:
	var neutral: Commander = _neutral_commander()
	if neutral == null:
		return []
	# An extractor is identified by its EnergyExtractor component, not by Entity.Type.
	return neutral.get_children().filter(
		func(n): return n is Commandable and n.has_node("EnergyExtractor")
	)


## The world/neutral commander (id 0), which owns every unowned map feature — extractors,
## extraction sites, shelters, and their Terrestrials — or null before the scenario is wired.
func _neutral_commander() -> Commander:
	if scenario == null:
		return null
	var neutrals := scenario.commanders.filter(func(c: Commander): return c.id == 0)
	return neutrals.front() if not neutrals.is_empty() else null


## The neutral Extractor closest to [from_position].
## Returns null when every Extractor on the map has already been claimed.
func nearest_neutral_extractor(a_from_position: Vector3) -> Commandable:
	var extractors := get_neutral_extractors()
	if extractors.is_empty():
		return null
	return (
		AU
		. sort_on_key(
			func(m: Commandable): return a_from_position.distance_squared_to(m.global_position),
			extractors
		)
		. front()
	)


# ─── INTERACTIONS (utility-gain opportunities) ──────────────────────────────


## Owned units that can perform interactions — those carrying an Interactor component
## (e.g. the Stock Truck, which deposits its prisoners at a camp). Identified by the
## component, so
## any future interactor unit is picked up.
func get_interactors() -> Array:
	return _owned_units().filter(func(u: Commandable): return u.interactor != null)


## Owned units that convert neutrals on contact — those carrying a Liberator component
## (e.g. Warlords). The set the opportunist draws liberation errands from.
func get_liberators() -> Array:
	return _owned_units().filter(func(u: Commandable): return u.liberator != null)


## Every loose neutral Terrestrial on the map. Like neutral extractors, these are world-owned
## map features the bot is aware of regardless of fog. Terrestrials held in a Garrison
## (already captured) are out of the tree and so never appear here.
func get_neutral_terrestrials() -> Array:
	var neutral: Commander = _neutral_commander()
	if neutral == null:
		return []
	return neutral.get_children().filter(
		func(n: Node):
			return n is Commandable and (n as Commandable).id == EntityIds.NT_BIO_LIGHT_TERRESTRIAL
	)


## What one liberation is worth to `a_liberator`, in energy: the cost of the unit its
## Liberator mints. 0 when the component has no conversion scene configured.
func liberation_value(a_liberator: Commandable) -> float:
	if a_liberator.liberator == null:
		return 0.0
	return float(_scene_unit_cost(a_liberator.liberator.converted_scene))


## Visible enemy units the bot can capture: biological-frame, non-structure, owned by
## an enemy. Fog-limited (visible_enemies only). The Colonial stock truck imprisons
## these for dominion.
func get_capturable_enemies() -> Array:
	return visible_enemies().filter(
		func(e: Commandable) -> bool:
			return (
				not e.structure_is_active()
				and EntityAttribute.evaluate(EntityAttribute.Type.IS_BIOLOGICAL, e)
			)
	)


## Energy cost of the unit a PackedScene spawns, via the tech tree (same convention as
## army_resource_value). Instantiates out of tree only to read the scene's piece id,
## then frees it. 0 when the scene isn't an Entity or the id isn't priced.
func _scene_unit_cost(a_packed: PackedScene) -> int:
	if a_packed == null:
		return 0
	var inst: Node = a_packed.instantiate()
	var t: StringName = inst.id if inst is Entity else &""
	inst.free()
	return unit_cost(t)


# ─── TECHNOLOGY / BUILD ORDER ───────────────────────────────────────────────


## The build/train preview instance for [type], or null when no tool produces it
## (e.g. an ability type). Lets the bot classify a catalog type by its SCENE's
## components instead of by the Entity.Type value. Reuses Commander's cached,
## out-of-tree preview instances.
func _preview_for_type(a_type) -> Node:
	var tool: Tool = Tool.for_type(a_type)
	return get_build_preview_instance(tool) if tool != null else null


## True when [type] builds a structure — detected by a "Structure" component on
## its preview scene rather than by reading the Entity.Type value.
func _type_is_structure(a_type) -> bool:
	var preview := _preview_for_type(a_type)
	return preview != null and preview.has_node("Structure")


## True when [type] trains a mobile unit — a producible scene with no "Structure"
## component. Excludes ability types (no producing tool, so no preview).
func _type_is_unit(a_type) -> bool:
	var preview := _preview_for_type(a_type)
	return preview != null and not preview.has_node("Structure")


## True when [type] is a COMBAT unit — its scene carries a Loadout with at least one
## Weapon. A unit with an empty Loadout (e.g. the colonial Stock Truck, whose utility
## role isn't wired yet) can't attack, so it returns false: the bot won't field it in
## attack waves or train it as army. Inspected on the cached build preview, so no
## per-type table is needed.
func unit_can_attack(a_type) -> bool:
	var preview := _preview_for_type(a_type)
	if preview == null:
		return false
	var loadout := preview.get_node_or_null("Loadout") as Loadout
	return loadout != null and loadout.has_weapons()


## True when [type] carries a weapon that can shoot something on the GROUND — read off the
## preview's weapon masks, which a scene sets and so survive being out of tree (the range
## shapes do not). The economy's prior for a static when nothing has been seen and no army
## stands to mirror: the first threat in a match walks.
func type_targets_ground(a_type) -> bool:
	var preview := _preview_for_type(a_type)
	if preview == null:
		return false
	var loadout := preview.get_node_or_null("Loadout") as Loadout
	if loadout == null:
		return false
	for child: Node in loadout.get_children():
		if (
			child is Weapon
			and (child as Weapon).target_mask & CollisionLayers.Mask.TARGETABLE_GROUND
		):
			return true
	return false


## True when [type] is a non-combat UTILITY unit worth fielding anyway — it can build
## structures (Builds) or perform interactions (Interactor), e.g. the Colonial Stock
## Truck. Lets production stand up a controlled number of these even though they can't
## attack. Inspected on the cached build preview, so no per-type table is needed.
func unit_is_utility(a_type) -> bool:
	var preview := _preview_for_type(a_type)
	if preview == null:
		return false
	return preview.has_node("Builds") or preview.has_node("Interactor")


# ─── WHAT A UTILITY TYPE IS FOR ─────────────────────────────────────────────
#
# WHICH ERRAND a utility type serves, asked of the TYPE rather than of an instance, because
# the consumer is production: BotProduction is deciding whether to make one more, and it has
# no instance to inspect. Each is read off the cached build preview, the same way
# unit_is_utility and unit_can_attack are, so a new utility unit classifies itself.
#
# The three exist because "how many utility units are too many" is a question about WORK
# (bot-architecture.md §What each module actually does, BotProduction): a builder is wanted
# per build job, a carrier per capture errand, and a unit that also fights is not waste when
# it has neither.


## True when [type] can construct structures — the builder half of the utility set.
func unit_type_can_build(a_type) -> bool:
	return _type_has_component(a_type, "Builds")


## True when [type] can take prisoners: a Garrison with room to put them in, which is what
## Garrison.can_capture asks of a captor. The DEPOSIT half (somewhere to bank them) is a
## structure question and belongs to the caller — a carrier with nowhere to unload has no
## errand, which is why BotOpportunist._gather_captures gates on get_deposit_structures().
func unit_type_can_capture(a_type) -> bool:
	var preview := _preview_for_type(a_type)
	var cage: Garrison = (
		preview.get_node_or_null("Garrison") as Garrison if preview != null else null
	)
	return cage != null and cage.capacity > 0


## True when [type] kills by driving over things — the TYPE-level form of unit_can_crush,
## read off the preview's Movement rather than off a live one.
func unit_type_can_crush(a_type) -> bool:
	var preview := _preview_for_type(a_type)
	var move: Movement = (
		preview.get_node_or_null("Locomotion") as Movement if preview != null else null
	)
	return move != null and move.can_crush_anything()


## Whether a unit of [type] can hurt the enemy at all — the TYPE-level form of
## unit_has_combat_utility (armed, or heavy enough to crush). The Colonial Stock Truck is
## the case that matters: it is a utility type by unit_is_utility AND army by
## BotMilitary._combat_units, so a production decision that treats it as pure overhead
## under-counts what it is buying.
func unit_type_has_combat_utility(a_type) -> bool:
	return unit_can_attack(a_type) or unit_type_can_crush(a_type)


## True when [type]'s scene carries the named component (e.g. "Production",
## "EnergyExtractor") — inspected on the cached build preview, so classification
## generalises without a per-type table.
func _type_has_component(a_type, a_component: String) -> bool:
	var preview := _preview_for_type(a_type)
	return preview != null and preview.has_node(a_component)


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
	return (
		Tool
		. tools_in_context(ControlBinding.ControlContext.BUILD)
		. map(func(t: Tool): return t.type)
		. filter(func(type): return caps.has(type) and has_tech_for(type))
	)


## Buildable structures that train units (carry a Production component) — the
## throughput buildings the economy expands (Redoubt, Hangar, …).
func buildable_production_structure_types() -> Array:
	return buildable_structure_types().filter(
		func(t): return Production.node_trains_units(_preview_for_type(t))
	)


## What the best combat unit `a_structure_type` could train is worth against `a_demand`
## (unit_composition_value) — how much the army wants what this building makes. 0 for a
## building that trains nothing armed. Read off the preview's Production component, so a
## new producer answers for itself.
func best_producible_value(a_structure_type, a_demand: Dictionary) -> float:
	var preview := _preview_for_type(a_structure_type)
	var production: Production = (
		preview.get_node_or_null("Production") as Production if preview != null else null
	)
	if production == null:
		return 0.0
	var best: float = 0.0
	for t: StringName in production.producible_types:
		if unit_can_attack(t):
			best = maxf(best, unit_composition_value(t, a_demand))
	return best


## Buildable structures that are STATIC DEFENCE: they carry weapons (a Loadout) and train
## nothing. A defence wants to stand where the enemy will come, which is a placement bearing
## (BotEconomy._wants_frontage); derived from components so a new turret classifies itself.
func buildable_defence_structure_types() -> Array:
	return buildable_structure_types().filter(
		func(t):
			return (
				_type_has_component(t, "Loadout")
				and not Production.node_trains_units(_preview_for_type(t))
			)
	)


## Buildable structures with a DockingBay — airfields. What they hold is the fragile half,
## so they want to sit BEHIND the base however many aircraft they train.
func buildable_docking_structure_types() -> Array:
	return buildable_structure_types().filter(func(t): return _type_has_component(t, "DockingBay"))


## Buildable structures that generate energy income (carry an EnergyExtractor — i.e.
## site-overlay extractors).
func buildable_income_structure_types() -> Array:
	return buildable_structure_types().filter(
		func(t): return _type_has_component(t, "EnergyExtractor")
	)


## Buildable structures this commander's dominion route earns from (the Colonial Compound,
## the Libertarian Opticon). Asked of the ROUTE, never of a component on the structure: a
## faction's dominion can be earned by a commander-level sweep that no single building carries.
## Empty for a faction whose route builds nothing (the Anarchist Warlord is trained).
func buildable_dominion_structure_types() -> Array:
	var route: DominionRoute = dominion_route()
	if route == null:
		return []
	return buildable_structure_types().filter(func(t): return route.structure_sources.has(t))


## How much more dominion this commander has a use for: what the sanctions it has not bought
## would cost, less what it has banked. 0 when the grid is bought out, empty (a faction with no
## sanctions), or already covered by the bank. What gates building ANOTHER source of a stacking
## dominion route (DominionRoute.another_source_adds_income): a Lab converts a site's energy into
## dominion, which is only worth doing while the dominion has something to buy.
func dominion_demand() -> int:
	if sanction_grid == null:
		return 0
	return maxi(0, sanction_grid.unowned_cost() - dominion)


## The faction's dedicated infrastructure provider (Faction.infrastructure_source), or &"" for a
## faction with none.
func infrastructure_source_type() -> StringName:
	return faction.infrastructure_source if faction != null else &""


## Whether the faction's infrastructure provider is a UNIT that is trained (the Technocratic
## Surveyor) rather than a structure that is built. Read off the provider's preview, so a
## faction declares nothing more than its infrastructure_source.
func infrastructure_source_is_unit() -> bool:
	var source: StringName = infrastructure_source_type()
	return source != &"" and _type_is_unit(source)


## Buildable structures that supply infrastructure (their preview's infrastructure > 0 — e.g.
## the Colonial power plant, Anarchical safehouse). The generic
## hook the economy uses to keep the commander out of infrastructure strain; the right
## faction-specific provider falls out of each faction's buildable set automatically.
func buildable_infrastructure_structure_types() -> Array:
	return buildable_structure_types().filter(func(t): return _type_provides_infrastructure(t))


## True when [type]'s build preview contributes infrastructure capacity (infrastructure > 0),
## inspected on the cached preview so no per-type table is needed.
func _type_provides_infrastructure(a_type) -> bool:
	var preview := _preview_for_type(a_type)
	return preview is Commandable and (preview as Commandable).infrastructure > 0


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
func unit_effectiveness_vs(a_unit_type, a_target: Commandable) -> float:
	# A hand-set matchup override wins over the computed multiplier (AOE, kiting, …
	# the damage table can't express — e.g. Kamikaze ≫ Irregular).
	var override: Variant = DamageTable.matchup_override(a_unit_type, a_target.id)
	if override != null:
		return override
	# `target` must be a LIVE instance: targetable_layers()/armour come from runtime
	# nodes (hurtbox), so a build PREVIEW would read 0 and break this. Effectiveness
	# is otherwise type-level, so any live instance of a type is representative.
	var my_preview := _preview_for_type(a_unit_type)
	if my_preview == null:
		return 0.0
	var loadout := my_preview.get_node_or_null("Loadout") as Loadout
	if loadout == null:
		return 0.0
	var by_crush: float = (
		CRUSH_EFFECTIVENESS
		if crushes(my_preview.get_node_or_null("Locomotion") as Movement, a_target)
		else 0.0
	)
	var w: Weapon = loadout.weapon_for_target(a_target)
	if w == null:
		return by_crush
	var base: float = w.per_shot_damage()
	if base <= 0.0:
		return by_crush
	return maxf(
		by_crush, DamageTable.calculate_damage(base, w.per_shot_damage_type(), a_target) / base
	)


## What running a unit over is worth, on the scale of the damage multiplier a weapon gets
## against its target (1.0 is a neutral matchup, a dedicated counter scores above it). A
## crush is a kill on contact, but under the bot's orders contact is incidental: an
## attack-moving vehicle stops to shoot, it does not drive through. MEASURED 2026-10-04
## (`sims/matildas_vs_recruits`, `sims/sloops_vs_recruits`): at cost parity two Matildas
## LOSE to twelve Recruits in three seeds of three, two Sloops beat ten in three of three. So
## a crusher is valued below a neutral matchup against what it could crush — enough that a
## vehicle is never read as useless against infantry, not enough to prefer it to a gun that
## actually counters them. Rises on the day the bot drives its vehicles through infantry.
const CRUSH_EFFECTIVENESS: float = 0.5


## Whether a unit moving as `a_mover` would crush `a_target` on contact: the size-class rule
## Movement.can_crush applies between two grounded movers; a structure or a flier is never
## crushed.
static func crushes(a_mover: Movement, a_target: Commandable) -> bool:
	if a_mover == null or a_target == null or a_target.movement == null:
		return false
	return a_mover.can_crush(a_target.movement)


# ─── ARMY COMPOSITION (effectiveness-driven counter-production) ──────────────

## How much less we value covering structures than enemy units — beating the enemy
## ARMY is the immediate goal; razing structures (warlords' job) is the longer game.
##
## A PARAMETER (BotDifficulty.structure_demand_weight, pushed in by BotBrain._apply_config),
## because it is the immediate game against the long one expressed as a single number, and
## it is what the production mix turns on. It lives HERE rather than on a manager because
## enemy_demand_map is perception; the brain writes it, nothing else does.
var structure_demand_weight: float = 0.4

## How fast a threat's demand falls once the army already covers it: demand is divided by
## `1 + coverage × this`. 1.0 is the plain diminishing-returns the demand map shipped with.
## 0 never saturates — the bot masses whatever counters the biggest threat and never
## diversifies — and a high value diversifies on the first unit that answers a type.
## A PARAMETER (BotDifficulty.demand_coverage_falloff).
var demand_coverage_falloff: float = 1.0


## Per believed enemy TYPE: { type -> { "demand": float, "rep": Commandable } }.
## demand = that type's summed importance across the believed-and-still-alive enemy
## comp (units 1.0, structures structure_demand_weight), DIVIDED DOWN by how well our
## current army already counters it — so a covered type has low demand (diminishing
## returns) and an unmet threat has high demand. `rep` is one live instance of the
## type, since effectiveness needs a live target (build previews read 0). Fog-limited:
## reads the blackboard's beliefs, restricted to entries whose entity is still alive.
func enemy_demand_map() -> Dictionary:
	if blackboard == null:
		return {}
	var importance: Dictionary = {}  # type -> summed importance
	var reps: Dictionary = {}  # type -> a live Commandable of that type
	for entry: CommanderBlackboard.Entry in blackboard.believed():
		if not is_instance_valid(entry.entity):
			continue
		var imp: float = structure_demand_weight if entry.is_structure else 1.0
		importance[entry.type] = importance.get(entry.type, 0.0) + imp
		if not reps.has(entry.type):
			reps[entry.type] = entry.entity

	# The enemy ALWAYS has a base to raze (the win condition), so guarantee a baseline
	# anti-structure target even when none is currently in view. Without this, a bot
	# that sees no enemy at all has zero demand and falls back to spamming the cheapest
	# unit — exactly the "keeps making irregulars" bug. Proxy the enemy's (unseen)
	# structures with one of our own (same armour class, a sound default otherwise).
	var sees_enemy_structure: bool = reps.values().any(
		func(r: Commandable): return r.structure_is_active()
	)
	if not sees_enemy_structure:
		var own_structs := _owned_structures()
		if not own_structs.is_empty():
			var s_rep: Commandable = own_structs[0]
			importance[s_rep.id] = importance.get(s_rep.id, 0.0) + structure_demand_weight
			reps[s_rep.id] = s_rep

	var own := _owned_units()
	var demand: Dictionary = {}
	for etype in importance:
		var rep: Commandable = reps[etype]
		var coverage: float = 0.0
		for u: Commandable in own:
			coverage += unit_effectiveness_vs(u.id, rep)
		demand[etype] = {
			"demand": importance[etype] / (1.0 + coverage * demand_coverage_falloff),
			"rep": rep,
		}
	return demand


## How valuable building one more [unit_type] is against the current demand map: its
## effectiveness vs each believed enemy type (using that type's live rep) × its demand.
func unit_composition_value(a_unit_type, a_demand: Dictionary) -> float:
	var total: float = 0.0
	for etype in a_demand:
		var d: Dictionary = a_demand[etype]
		total += unit_effectiveness_vs(a_unit_type, d["rep"]) * d["demand"]
	return total


# ─── AOE-SUICIDE UNITS (kamikaze cost-effectiveness) ────────────────────────


## Energy cost of a type, from the tech tree.
func unit_cost(a_unit_type) -> int:
	var spec: TechnologySpec = technology_mapping.get(a_unit_type)
	return spec.energy_cost if spec != null else 0


## Physics ticks a unit of [type] takes to produce, from the tech tree. 0 when the type is
## unpriced. Together with unit_cost this is what a unit costs to REPLACE — the pair the
## scout scorer reads to prefer risking something cheap and quickly remade.
func unit_build_time_ticks(a_unit_type) -> int:
	var spec: TechnologySpec = technology_mapping.get(a_unit_type)
	return spec.creation_time if spec != null else 0


## Total energy value of the enemy's army AS THE BOT BELIEVES IT — sum of the build cost
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


func aoe_suicide_profile(a_unit_type) -> Variant:
	if _aoe_profile_cache.has(a_unit_type):
		return _aoe_profile_cache[a_unit_type]
	var profile: Variant = _compute_aoe_suicide_profile(a_unit_type)
	_aoe_profile_cache[a_unit_type] = profile
	return profile


func _compute_aoe_suicide_profile(a_unit_type) -> Variant:
	var unit_preview := _preview_for_type(a_unit_type)
	if unit_preview == null:
		return null
	var loadout := unit_preview.get_node_or_null("Loadout") as Loadout
	if loadout == null:
		return null
	for w: Weapon in loadout.get_weapons():
		if w.projectile_scene == null:
			continue
		var proj: Node = w.projectile_scene.instantiate()
		var suicide: bool = not (
			proj.find_children("*", "SuicideStatusEffect", true, false).is_empty()
		)
		var radius: float = _projectile_blast_radius(proj)
		var dmg: Variant = proj.get("base_damage")
		var dtype: Variant = proj.get("damage_type")
		proj.free()
		if suicide and radius > 0.0 and dmg != null:
			return {"radius": radius, "damage": float(dmg), "type": dtype}
	return null


func _projectile_blast_radius(a_proj: Node) -> float:
	var hit := a_proj.get_node_or_null("HitShape") as CollisionShape3D
	if hit == null or RangeShapes.radius_of(hit.shape) < 0.0:
		return 0.0
	# Out-of-tree, so use local transforms: blast radius scales with the projectile
	# root and the shape node's own X scale.
	return (
		RangeShapes.radius_of(hit.shape)
		* (a_proj as Node3D).scale.x
		* hit.transform.basis.x.length()
	)


## True when [unit] is an AOE-suicide unit (has an aoe_suicide_profile).
func is_suicide_aoe_unit(a_unit: Commandable) -> bool:
	return aoe_suicide_profile(a_unit.id) != null


## Owned AOE-suicide units (the ones BotKamikaze micromanages).
func get_suicide_aoe_units() -> Array:
	return _owned_units().filter(func(u: Commandable): return is_suicide_aoe_unit(u))


## The most COST-EFFECTIVE blast target for [kamikaze], or null if none clears the
## bar. For each visible enemy unit (a blast centre), the hit's value is summed over
## the enemy units the blast would catch: (HP-fraction it removes) × (their energy cost).
## A run is worth it only when that value beats the drone's own cost — i.e. the blast
## destroys more than it spends. Returns { "target": Commandable, "value": float }.
func kamikaze_best_target(a_kamikaze: Commandable) -> Variant:
	var profile: Variant = aoe_suicide_profile(a_kamikaze.id)
	if profile == null:
		return null
	# Buildings are never the CENTRE of a blast (nor part of its value): a drone is spent on
	# bodies. Everything else is scored through the shared coverage query.
	#
	# …and only bodies THIS drone can actually strike. The scan used to price a blast purely
	# off the damage table, which answers for anything with armour — including an enemy Scan
	# drone hovering on the AIR layer that a ground-ramming kamikaze has no targeting mode
	# for. Anchoring on one produced a `persist = true` Attack the drone could never act on
	# and never drop, so it flew over and waited out the drone's lifespan instead of being
	# HELD for a blast worth spending itself on. Filtering the candidate set (rather than only
	# the anchor) keeps the valuation conservative: a blast is priced by what the drone can
	# reach, never by bystanders it cannot. The question is `unit_can_shoot`, not
	# `unit_can_damage`: a drone delivers a BLAST, and being heavy enough to drive over
	# something is not a way of getting a bomb onto it.
	var units: Array = visible_enemies().filter(
		func(e: Commandable): return not e.structure_is_active() and unit_can_shoot(a_kamikaze, e)
	)
	var best: Dictionary = best_covered_point(
		units, profile["radius"], func(u: Commandable): return _aoe_unit_value(u, profile)
	)
	if best["anchor"] != null and best["weight"] >= float(unit_cost(a_kamikaze.id)):
		return {"target": best["anchor"], "value": best["weight"]}
	return null


## What blasting one unit is worth, in energy: the fraction of it the blast actually removes,
## priced at its build cost. Capped at the unit's remaining HP, so overkill is not paid for.
func _aoe_unit_value(a_unit: Commandable, a_profile: Dictionary) -> float:
	if a_unit.defense == null or a_unit.defense.hp_max <= 0.0:
		return 0.0
	var effective: float = DamageTable.calculate_damage(
		a_profile["damage"], a_profile["type"], a_unit
	)
	var fraction: float = minf(effective, a_unit.defense.hp) / a_unit.defense.hp_max
	return fraction * float(unit_cost(a_unit.id))


## True when all prerequisite structures for [type] have been built,
## regardless of whether we can currently afford to produce it.
func has_tech_for(a_type: StringName) -> bool:
	var spec: TechnologySpec = technology_mapping.get(a_type)
	return spec != null and spec.unmet_need == TechnologySpec.UnmetNeed.NONE


## Whether training `a_unit_type` needs a `a_structure_type` standing — read off the tech
## tree (TechnologySpec.required_structures), so a tech structure is whatever some unit
## requires rather than a list anyone maintains.
func unit_requires_structure(a_unit_type: StringName, a_structure_type: StringName) -> bool:
	var spec: TechnologySpec = technology_mapping.get(a_unit_type)
	return spec != null and spec.required_structures.has(a_structure_type)


## All Entity.Types whose prerequisite structures are satisfied — the full
## set of things we are currently able to build or train, ignoring cost.
func unlocked_types() -> Array:
	# Piece ids only — the map also carries int Ability.Type gate keys.
	return technology_mapping.keys().filter(func(t): return t is StringName and has_tech_for(t))


## Structure types whose tech prerequisite is NOT yet met — each one
## represents a potential tech-tree expansion the bot could invest in.
func locked_structure_types() -> Array:
	return technology_mapping.keys().filter(
		func(t): return t is StringName and _type_is_structure(t) and not has_tech_for(t)
	)


## The most advanced unit type currently unlocked for training. Unit-vs-structure
## is decided by the type's scene (no "Structure" component); "most advanced"
## ranks by energy cost (ids are strings now, so the old enum-value ordering is
## gone — cost is the tech catalog's de-facto advancement axis), with the id as
## a deterministic tiebreak. Returns &"" when no units are available yet.
func highest_unlocked_unit_type() -> StringName:
	var unit_types := unlocked_types().filter(func(t): return _type_is_unit(t))
	if unit_types.is_empty():
		return &""
	unit_types.sort_custom(
		func(a, b) -> bool:
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
