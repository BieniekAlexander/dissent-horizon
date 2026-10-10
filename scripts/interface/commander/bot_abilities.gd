class_name BotAbilities
extends RefCounted

## BotAbilities — casts the LOCAL abilities the bot's pieces carry: the ones a UNIT holds and
## uses where it stands, as opposed to the commander-level sanctions BotSanction aims. Which
## pieces carry what is read off their `Abilities` pools, never known by name; what an ability
## is FOR is read off its doc's `command:`, which is the player's own route:
##
##   • `command_launch` — a STRIKE (the Recruit's Irradiate): thrown at the clump of visible
##     enemies the payload would cover best, within the ability's reach of the caster, and
##     only where none of our own would be under it — the blast does not take sides.
##   • `command_spot` — the Colonial SIEGE LOOP: while a loaded Bombard waits for ground, a
##     spotter is sent to call a solution in on the nearest believed enemy structure and holds
##     it there; the gun answers on its own (automatic fire). One spotter out per loaded gun.
##   • `command_bombard` — THE GUN'S OWN SHOT: a loaded gun fires at the most valuable visible
##     enemy standing on ground its side already spots, none of ours under the blast. Automatic
##     fire answers only a HELD beacon, so without this a Sleeper's planted beacon, a Beacon
##     Drop's, and the ground a Reverence or a Watch Tower covers were spotted for nobody.
##
## A passive ability has nothing to cast. An ability whose command this module does not know
## is left alone, and is what the piece-usage audit reports as NO_ACTUATION.
## gdd/systems/ai/bot-architecture.md §Local abilities.

## Work units per piece with an ability pool looked at.
const UNIT_WORK_UNITS: int = 40

## Spotting is an ERRAND: the spotter holds its solution until a gun fires on it, and the army
## may not sweep it away meanwhile.
const CLAIM_OWNER: StringName = &"abilities"

## A strike wants at least this many enemies under it. One is a rifle's job; the charge is
## for a clump.
const STRIKE_MIN_TARGETS: int = 2

## How far short of a believed structure a spotter's walk may end and still count as reaching
## it — the structure's half-footprint plus the standoff, as BotMilitary.REACH_TOLERANCE.
const SPOT_REACH_TOLERANCE: float = 8.0

var _bot: Bot
var _act: BotActuator
## Which manager owns which unit; the brain replaces this with the bot's shared registry.
var claims: BotClaims = BotClaims.new()


func _init(a_bot: Bot, a_act: BotActuator) -> void:
	_bot = a_bot
	_act = a_act


## Returns the work units spent.
func tick() -> int:
	_release_finished_spotters()
	var considered: int = 0
	var guns_wanting_ground: int = _loaded_gun_count() - _spotters_out()
	for unit: Actor in _bot.get_units():
		var pool: Abilities = unit.get_node_or_null("Abilities") as Abilities
		if pool == null:
			continue
		considered += 1
		for id: StringName in pool.granted_abilities():
			if (
				AbilityCatalog.is_passive(id)
				or not pool.is_ready(id)
				or not UpgradeCatalog.is_ability_unlocked(unit, id)
			):
				continue
			match AbilityCatalog.command_of(id):
				"command_launch":
					if _strike(unit, id):
						break
				"command_spot":
					if guns_wanting_ground > 0 and _spot(unit):
						guns_wanting_ground -= 1
						break
	for gun: Actor in _loaded_guns():
		considered += 1
		_fire(gun)
	return considered * UNIT_WORK_UNITS


#region Strikes
## Throw `a_id` where it covers the most visible enemies within reach, if that is a clump and
## none of ours stand under it. A unit mid-fight is the usual caster — it is the one with
## enemies in reach — and a one-shot order replaces its Attack for the throw; the targeting
## manager re-engages it after. A unit on an errand or under exclusive management is left to
## its job. Returns whether a cast was ordered.
func _strike(a_unit: Actor, a_id: StringName) -> bool:
	if claims.priority_of(a_unit) >= BotClaims.Priority.ERRAND:
		return false
	if a_unit.current_command() is Ability:
		return false  # already throwing
	var reach: float = AbilityCatalog.range_for(a_id, a_unit)
	var blast: float = AbilityCatalog.blast_radius_of(a_id)
	if blast <= 0.0:
		return false  # a single-piece payload has no clump to aim at
	var enemies: Array = _bot.visible_enemies_near(a_unit.global_position, reach)
	if enemies.size() < STRIKE_MIN_TARGETS:
		return false
	var cluster: Dictionary = _bot.best_covered_point(
		enemies, blast, func(_u: Node3D) -> float: return 1.0
	)
	if int(cluster["weight"]) < STRIKE_MIN_TARGETS:
		return false
	var centre: Vector3 = cluster["center"]
	if _any_own_unit_within(centre, blast):
		return false
	return _act.use_ability(a_unit, a_id, centre)


func _any_own_unit_within(a_point: Vector3, a_radius: float) -> bool:
	return _bot.get_units().any(
		func(u: Actor) -> bool:
			return VU.in_xz(u.global_position).distance_to(VU.in_xz(a_point)) <= a_radius
	)


#endregion


#region The siege loop
## Send `a_spotter` to call a solution in on the nearest believed enemy structure its walk can
## reach, and claim it for the errand. Returns whether it was sent.
func _spot(a_spotter: Actor) -> bool:
	if not claims.can_claim(a_spotter, CLAIM_OWNER, BotClaims.Priority.ERRAND):
		return false
	if a_spotter.current_command() is Spot:
		return false
	var origin: Vector3 = a_spotter.global_position
	var target: CommanderBlackboard.Entry = _bot.nearest_believed_enemy_structure_entry(
		func(entry: CommanderBlackboard.Entry) -> bool:
			return _bot.is_reachable(origin, entry.last_known_location, SPOT_REACH_TOLERANCE)
	)
	if target == null:
		return false
	if not _act.spot(a_spotter, target.last_known_location):
		return false
	claims.claim(a_spotter, CLAIM_OWNER, BotClaims.Priority.ERRAND)
	return true


## Give back every spotter whose solution has ended — a gun fired on it, or it was re-ordered.
func _release_finished_spotters() -> void:
	for unit: Variant in claims.units_of(CLAIM_OWNER):
		if not is_instance_valid(unit) or not ((unit as Actor).current_command() is Spot):
			claims.release(unit, CLAIM_OWNER)


## How many owned, finished guns hold a Bombard charge right now — read off the pieces, so a
## second battery is a second solution wanted.
func _loaded_gun_count() -> int:
	return _loaded_guns().size()


## The owned, finished guns holding a Bombard charge and not already ordered to fire.
func _loaded_guns() -> Array:
	return _bot.get_structures().filter(_is_loaded_gun)


func _is_loaded_gun(a_structure: Actor) -> bool:
	var pool: Abilities = a_structure.get_node_or_null("Abilities") as Abilities
	if pool == null or not a_structure.is_built:
		return false
	var charged: bool = pool.granted_abilities().any(
		func(id: StringName) -> bool:
			return AbilityCatalog.command_of(id) == "command_bombard" and pool.is_ready(id)
	)
	var ordered: bool = a_structure.get_command_chain().any(
		func(command: MoveCommand) -> bool: return command is Bombard
	)
	return charged and not ordered


## THE GUN'S OWN SHOT: fire `a_gun` at the visible enemy, standing on spotted ground, whose
## blast catches the most VALUE — each enemy under it weighed at its cost, the currency every
## bot comparison uses — and never with one of ours under it. Spotted ground is asked of
## BombardTargeting, the one place the game answers it, so a shot inside the gun's own bubble,
## a tower's or a Reverence's costs nothing and a shot on a planted beacon spends it, exactly as
## the player's would. The point fired on is the anchoring enemy's own, so it is spotted by
## construction (the blast's centroid might not be). Returns whether a shot was ordered.
func _fire(a_gun: Actor) -> bool:
	if a_gun.commander == null:
		return false
	var spotted: Array = _bot.visible_enemies().filter(
		func(enemy: Actor) -> bool:
			return BombardTargeting.is_spotted(a_gun.commander, enemy.global_position)
	)
	if spotted.is_empty():
		return false
	var blast: float = AbilityCatalog.blast_radius_of(Bombard.ABILITY_ID)
	var cluster: Dictionary = _bot.best_covered_point(
		spotted,
		blast,
		func(enemy: Actor) -> float: return maxf(1.0, float(_bot.unit_cost(enemy.id)))
	)
	var anchor: Variant = cluster["anchor"]
	if anchor == null:
		return false
	var point: Vector3 = (anchor as Actor).global_position
	if _any_own_unit_within(point, blast):
		return false
	return _act.bombard(a_gun, point)


func _spotters_out() -> int:
	return claims.units_of(CLAIM_OWNER).size()
#endregion
