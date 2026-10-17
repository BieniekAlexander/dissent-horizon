class_name SimulationDigest
extends RefCounted

## A short hash of everything the simulation is currently made of — the determinism check's
## whole instrument, shared by the self-play harness, replay and (PLANNED) netplay. Two runs of
## one seed must produce the same digest at the same tick; the first tick at which they differ
## is where the divergence entered. gdd/systems/commands/recording-and-replay.md §Detecting drift,
## gdd/systems/commands/netplay.md §Decisions.
##
## COVERAGE: everything a physics tick governs, not only where pieces stand. A divergence in an
## order queue, a cooldown, a production job or a random draw is otherwise invisible until it
## moves a unit or changes its HP, which can be many seconds later. The list below is also the
## first draft of the state inventory a rollback snapshot needs (netplay.md §Rollback, later):
##   * the gameplay random stream (`SU.rng`) and every bot brain's own stream;
##   * per commander: energy, dominion, the production queue's length, upgrades owned, whether
##     it is eliminated;
##   * per piece: position, velocity, HP, its command chain (each command's class, target and
##     destination), every weapon's split, reload and ammo, its production jobs and the ticks
##     left on them, every ability pool's charges and recharge, and its active status effects;
##   * every other entity a commander holds (an emission in flight, say): where it is.
## TODO: Godot's GLOBAL generator, which authored `Expression`s draw from, has no readable state,
## so it is not covered; a draw from it that diverges shows only through what it changes.
##
## SORTED before hashing, and that is the load-bearing part: entity order within a commander
## follows tree order, which is not something the simulation guarantees. Pieces are sorted by
## `Entity.spawn_serial` — handed out in spawn order, so the same on every machine — and each
## one's line leads with it, so a diff of two state strings names the exact piece that drifted.
## An entity without a serial (an emission is not a piece) sorts after the pieces, by its line.

## How many hex characters of the SHA-256 a digest keeps: enough that two different states
## colliding is not a concern, short enough to read in a log line.
const DIGEST_LENGTH: int = 16
## 10 to the power of each number of decimal places `fixed` is asked for.
const _DECIMAL_SCALES: Array[int] = [1, 10, 100, 1000, 10000]


static func of(scenario: Scenario) -> String:
	return state_string(scenario).sha256_text().substr(0, DIGEST_LENGTH)


## The digest's INPUT, before hashing. A mismatched digest says only THAT two runs differ — this
## says WHICH entity, which is the whole of a divergence hunt.
static func state_string(scenario: Scenario) -> String:
	var parts: PackedStringArray = ["rng:%d" % SU.rng.state]
	for commander: Commander in scenario.commanders:
		if commander == null:
			continue
		parts.append(_commander_part(commander))
	return "|".join(parts)


static func _commander_part(a_commander: Commander) -> String:
	var serialed: Array = []
	var unserialed: PackedStringArray = []
	for child: Node in a_commander.get_children():
		var entity := child as Entity
		if entity == null or entity.is_queued_for_deletion():
			continue
		if entity.spawn_serial != 0:
			serialed.append([entity.spawn_serial, _entity_line(entity)])
		else:
			unserialed.append(_entity_line(entity))
	serialed.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	unserialed.sort()
	var lines: PackedStringArray = []
	for entry: Array in serialed:
		lines.append(str(entry[1]))
	lines.append_array(unserialed)

	var bot_rng: String = "-"
	var bot := a_commander as Bot
	if bot != null and bot.brain() != null and bot.brain().rng != null:
		bot_rng = str(bot.brain().rng.state)
	var queued: int = (
		a_commander.production_queue.entries.size() if a_commander.production_queue != null else 0
	)
	return (
		"c%d:e%d:d%d:q%d:u%d:x%d:r%s:%s"
		% [
			a_commander.id,
			a_commander.energy,
			a_commander.dominion,
			queued,
			a_commander.owned_upgrades().size(),
			1 if a_commander.is_eliminated else 0,
			bot_rng,
			";".join(lines),
		]
	)


## `a_value` to `a_decimals` places, as text that is the same on every platform. Rounded by
## arithmetic, never by "%.3f": string formatting is the platform's, and a value on an exact tie
## (-39.5625 to three places) rounds to even on one platform and away from zero on another
## (measured 2026-10-14) — a digest that differs where the simulation does not.
static func fixed(a_value: float, a_decimals: int) -> String:
	var scale: int = _DECIMAL_SCALES[a_decimals]
	var units: int = roundi(a_value * scale)
	var minus: String = "-" if units < 0 else ""
	var whole: int = absi(units) / scale
	var part: String = str(absi(units) % scale).pad_zeros(a_decimals)
	return "%s%d.%s" % [minus, whole, part] if a_decimals > 0 else "%s%d" % [minus, whole]


static func fixed_vector(a_vector: Vector3, a_decimals: int) -> String:
	return ",".join(
		[
			fixed(a_vector.x, a_decimals),
			fixed(a_vector.y, a_decimals),
			fixed(a_vector.z, a_decimals)
		]
	)


static func _entity_line(a_entity: Entity) -> String:
	var at: Vector3 = a_entity.global_position
	var line: String = "#%d %s@%s" % [a_entity.spawn_serial, a_entity.id, fixed_vector(at, 3)]
	var actor := a_entity as Actor
	if actor == null:
		return line
	var hp: float = actor.defense.hp if actor.defense != null else 0.0
	var v: Vector3 = actor.velocity
	line += " hp%s v%s" % [fixed(hp, 2), fixed_vector(v, 3)]
	line += " c[%s]" % _commands(actor)
	line += " w[%s]" % _weapons(actor)
	line += " p[%s]" % _production(actor)
	line += " a[%s]" % _abilities(actor)
	line += " s[%s]" % _effects(actor)
	return line


## Each command in the chain, current first: its class, the serial of its target and where it
## is headed.
static func _commands(a_actor: Actor) -> String:
	if a_actor.command_receiver == null:
		return ""
	var out: PackedStringArray = []
	for command: MoveCommand in a_actor.command_receiver.get_command_chain():
		if command == null:
			continue
		var script: Script = command.get_script()
		var kind: String = String(script.get_global_name()) if script != null else "?"
		var target_serial: int = 0
		var to: Vector3 = Vector3.ZERO
		if command.message != null:
			if is_instance_valid(command.message.target):
				target_serial = command.message.target.spawn_serial
			to = command.message.world_position
		out.append("%s>%d@%s" % [kind, target_serial, fixed_vector(to, 2)])
	return ",".join(out)


static func _weapons(a_actor: Actor) -> String:
	if a_actor.weapon_inventory == null:
		return ""
	var out: PackedStringArray = []
	# Every weapon, live or not, so a waiting scavenged weapon's state is still compared; the
	# marker is added only once scavenged, leaving every other piece's token as it was.
	if a_actor.weapon_inventory.is_scavenged:
		out.append("scavenged")
	for weapon: Weapon in a_actor.weapon_inventory.all_weapons():
		out.append(weapon.digest_token())
	return ",".join(out)


static func _production(a_actor: Actor) -> String:
	if a_actor.production == null:
		return ""
	return "%d/%d" % [a_actor.production.job_count(), a_actor.production.remaining_ticks()]


static func _abilities(a_actor: Actor) -> String:
	var abilities := a_actor.get_node_or_null("Abilities") as Abilities
	if abilities == null:
		return ""
	var out: PackedStringArray = []
	for i: int in abilities.pool_count():
		out.append(
			"%d:%s" % [abilities.pool_charges(i), fixed(abilities.pool_recharge_fraction(i), 4)]
		)
	return ",".join(out)


static func _effects(a_actor: Actor) -> String:
	var out: PackedStringArray = []
	for child: Node in a_actor.get_children():
		var effect := child as StatusEffect
		if effect == null or not effect.is_active():
			continue
		var script: Script = effect.get_script()
		var kind: String = String(script.get_global_name()) if script != null else "?"
		out.append("%s:x%d:%s" % [kind, effect.stacks, fixed(effect.remaining_fraction(), 4)])
	out.sort()
	return ",".join(out)
