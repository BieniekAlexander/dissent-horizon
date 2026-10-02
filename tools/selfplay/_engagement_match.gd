extends "res://tools/selfplay/run_match.gd"

## TEMPORARY engagement probe (delete me when it stops earning its place).
##
## The question it exists to answer, from the 2026-09-10 feedback: "armies move out but never
## engage" and "units are ordered onto targets their weapons cannot touch". Both are claims
## about a unit STANDING NEXT TO SOMETHING IT CANNOT HURT, so that is made directly
## countable here rather than inferred from army-value curves.
##
## Per slot per sample, over the bot's own combat units (BotMilitary._combat_units):
##   • objective_kind   — WHICH branch of BotMilitary._objective_for produced the march
##                        target. "unit_belief" is the ghost-march: the last place a
##                        wandering enemy SCOUT was seen.
##   • arrived/stalled  — units standing at the objective, and how many of them hold no
##                        Attack.
##   • beside_untargetable — units with a VISIBLE enemy inside their own weapon reach that
##                        NO weapon they carry can target, and nothing in that reach they
##                        can. This is the untargetable-commitment rate.
##   • objective_untargetable — the objective itself has a visible enemy on it that no
##                        member of this army can damage.
## Plus a death ledger split by whether the dead unit was SCOUTING, which is the asymmetry
## the report describes ("only units getting caught in combat are units which are scouting").

## How close a unit has to be to the army objective to count as having ARRIVED. Wider than
## BotMilitary.OBJECTIVE_EPSILON because `nearest_navmesh_point` moves the destination and
## the units spread out around it.
const ARRIVE_RADIUS: float = 6.0
## Floor on the radius a unit is asked "is there anything here you cannot hurt" over, for a
## unit whose weapons are shorter than this (or which carries none).
const MIN_LOOK_RADIUS: float = 5.0

## instance id -> {"slot": int, "scouting": bool, "hurt": bool} for every unit seen alive.
var _tracked: Dictionary = {}
## Per slot: cumulative deaths, split.
var _deaths_scout: Array[int] = [0, 0]
var _deaths_army: Array[int] = [0, 0]
var _deaths_scout_combat: Array[int] = [0, 0]
var _deaths_army_combat: Array[int] = [0, 0]

## Ticks between roster scans. Not every tick: the scan walks both rosters and costs real
## time in a harness whose whole point is running many matches, and a unit cannot be born,
## fight and die inside a third of a second.
const LEDGER_SCAN_TICKS: int = 30

var _ledger_countdown: int = 0


func _physics_process(_delta: float) -> void:
	if _scenario == null:
		return
	_ledger_countdown -= 1
	if _ledger_countdown > 0:
		return
	_ledger_countdown = LEDGER_SCAN_TICKS
	_refresh_ledger()


## Walk both slots' live units, remember which are scouting and which have taken damage, and
## bank a death for anything that has left the roster since the last tick. Done by DIFF
## rather than off `entity_occurrence` because a unit that dies is freed before a sample can
## ask it anything, and the roster diff needs no signal wiring per spawn.
func _refresh_ledger() -> void:
	var alive: Dictionary = {}
	for i: int in _scenario.player_slots.size():
		var brain: BotBrain = _brain_for_slot(i)
		if brain == null or brain.bot == null:
			continue
		var scout: BotScout = brain.get_scout()
		var scouting: Dictionary = {}
		if scout != null:
			for s: Commandable in scout._scouts:
				if is_instance_valid(s):
					scouting[s.get_instance_id()] = true
		for u: Commandable in brain.bot.get_units():
			var key: int = u.get_instance_id()
			alive[key] = true
			var rec: Dictionary = _tracked.get(key, {"slot": i, "scouting": false, "hurt": false})
			rec["slot"] = i
			if scouting.has(key):
				rec["scouting"] = true  # STICKY: it was scouting when it met the enemy
			if u.defense != null and u.defense.hp < u.defense.hp_max:
				rec["hurt"] = true
			_tracked[key] = rec
	for key: int in _tracked.keys():
		if alive.has(key):
			continue
		var rec: Dictionary = _tracked[key]
		var slot: int = rec["slot"]
		if rec["scouting"]:
			_deaths_scout[slot] += 1
			if rec["hurt"]:
				_deaths_scout_combat[slot] += 1
		else:
			_deaths_army[slot] += 1
			if rec["hurt"]:
				_deaths_army_combat[slot] += 1
		_tracked.erase(key)


func _brain_sample(a_brain: BotBrain) -> Dictionary:
	var base: Dictionary = super._brain_sample(a_brain)
	if a_brain == null or a_brain.bot == null:
		return base
	var bot: Bot = a_brain.bot
	var military: BotMilitary = a_brain._military
	if military == null:
		return base
	base["objective_kind"] = _objective_kind(bot, military)
	base["objective"] = "%d,%d" % [int(military._objective.x), int(military._objective.z)]

	var army: Array = military._combat_units(bot.get_units())
	var objective: Vector3 = military._objective
	var arrived: int = 0
	var attacking: int = 0
	var stalled: int = 0
	var beside_untargetable: int = 0
	for u: Commandable in army:
		var is_attacking: bool = (
			u.has_command()
			and u.current_command() is Attack
			and is_instance_valid((u.current_command() as Attack).message.target)
		)
		if is_attacking:
			attacking += 1
		var near_objective: bool = (
			VU.in_xz(u.global_position).distance_to(VU.in_xz(objective)) <= ARRIVE_RADIUS
		)
		if near_objective:
			arrived += 1
			if not is_attacking:
				stalled += 1
		if not is_attacking and _is_beside_untargetable(bot, u):
			beside_untargetable += 1

	base["army"] = army.size()
	base["attacking"] = attacking
	base["arrived"] = arrived
	base["stalled"] = stalled
	base["beside_untargetable"] = beside_untargetable
	base["objective_untargetable"] = _objective_is_untargetable(bot, army, objective)
	var belief: Dictionary = _objective_belief(bot, military, army)
	base["belief_type"] = belief["type"]
	base["belief_age"] = snappedf(belief["age"], 0.1)
	base["belief_damageable"] = belief["damageable"]
	base["belief_dist_home"] = snappedf(belief["dist_home"], 0.1)
	var slot: int = _slot_of(bot)
	if slot >= 0:
		base["deaths_scout"] = _deaths_scout[slot]
		base["deaths_army"] = _deaths_army[slot]
		base["deaths_scout_combat"] = _deaths_scout_combat[slot]
		base["deaths_army_combat"] = _deaths_army_combat[slot]
	return base


func _slot_of(a_bot: Bot) -> int:
	for i: int in _scenario.player_slots.size():
		var brain: BotBrain = _brain_for_slot(i)
		if brain != null and brain.bot == a_bot:
			return i
	return -1


## Which branch of BotMilitary._objective_for produced the standing objective.
func _objective_kind(a_bot: Bot, a_military: BotMilitary) -> String:
	match a_military.current_posture():
		BotMilitary.Posture.DEFEND:
			return "defend"
		BotMilitary.Posture.ATTACK:
			if a_bot.nearest_believed_enemy_structure_position() != null:
				return "structure_belief"
			if a_bot.nearest_believed_enemy_unit_position(a_bot.base_centroid()) != null:
				return "unit_belief"
			return "none"
		_:
			return "home"


## THE BELIEF THE ATTACK OBJECTIVE CAME FROM, mirroring BotMilitary._objective_for's choice:
## nearest believed STRUCTURE to base, else nearest believed UNIT to home. Reported as
## {type, age (seconds since the sighting), damageable (any army member carries a weapon
## that can target the remembered entity), dist_home}.
##
## `damageable` is the question the whole report turns on: the objective is chosen from a
## POSITION, and nothing on the way to it ever asks whether the thing remembered there is
## something this army can hurt.
func _objective_belief(a_bot: Bot, a_military: BotMilitary, a_army: Array) -> Dictionary:
	var out: Dictionary = {"type": "", "age": -1.0, "damageable": true, "dist_home": -1.0}
	if a_military.current_posture() != BotMilitary.Posture.ATTACK or a_bot.blackboard == null:
		return out
	var home: Vector3 = a_military._home_anchor_position()
	var entries: Array = a_bot.blackboard.believed_structures()
	var origin: Vector3 = a_bot.base_centroid()
	if entries.is_empty():
		entries = a_bot.blackboard.believed_units()
		origin = home
	var best: CommanderBlackboard.Entry = null
	var best_d: float = INF
	for e: CommanderBlackboard.Entry in entries:
		var d: float = origin.distance_squared_to(e.last_known_location)
		if d < best_d:
			best_d = d
			best = e
	if best == null:
		return out
	out["type"] = String(best.type)
	out["age"] = a_bot.seconds_elapsed() - best.last_seen_time
	out["dist_home"] = home.distance_to(best.last_known_location)
	out["damageable"] = _army_can_damage(a_army, best.entity)
	return out


## Can ANY member of `a_army` take HP off `a_target`? Asked through the production predicate
## (`Bot.any_unit_can_damage`) rather than re-implemented, so the measurement and the fix are
## the same question — an instrument that asked a narrower one would report a rate the fix
## could never move.
func _army_can_damage(a_army: Array, a_target: Variant) -> bool:
	return Bot.any_unit_can_damage(a_army, a_target)


## THE COUNT THE REPORT IS ABOUT: is `a_unit` standing within its own reach of a visible
## enemy that nothing it carries can target, with nothing in that same reach that it can?
func _is_beside_untargetable(a_bot: Bot, a_unit: Commandable) -> bool:
	if a_unit.weapon_inventory == null:
		return false
	var reach: float = MIN_LOOK_RADIUS
	for w: Weapon in a_unit.weapon_inventory.get_weapons():
		reach = maxf(reach, w.ground_reach())
	var saw_untargetable: bool = false
	for e in a_bot.get_enemies_near(a_unit.global_position, reach):
		var c := e as Commandable
		if c == null or not c.is_visible_to(a_bot.id):
			continue
		if a_unit.weapon_inventory.weapon_for_target(c) != null:
			return false  # something here it CAN hurt: not the failure mode
		saw_untargetable = true
	return saw_untargetable


## Is there a visible enemy sitting on the army's objective that NO member of this army can
## damage? That is an army committed to a target it cannot act on.
func _objective_is_untargetable(a_bot: Bot, a_army: Array, a_objective: Vector3) -> bool:
	var found: bool = false
	for e in a_bot.get_enemies_near(a_objective, ARRIVE_RADIUS):
		var c := e as Commandable
		if c == null or not c.is_visible_to(a_bot.id):
			continue
		found = true
		for u: Commandable in a_army:
			if u.weapon_inventory != null and u.weapon_inventory.weapon_for_target(c) != null:
				return false
	return found
