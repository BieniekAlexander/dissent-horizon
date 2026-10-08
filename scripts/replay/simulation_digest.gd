class_name SimulationDigest
extends RefCounted

## A short hash of everything the simulation is currently made of — the determinism check's
## whole instrument, shared by the self-play harness and replay. Two runs of one seed must
## produce the same digest at the same tick; the first tick at which they differ is where the
## divergence entered. gdd/systems/commands/recording-and-replay.md §Detecting drift.
##
## SORTED before hashing, and that is the load-bearing part: entity order within a commander
## follows tree order, which is not something the simulation guarantees. An unsorted digest
## would report divergence that is not there.

## How many hex characters of the SHA-256 a digest keeps: enough that two different states
## colliding is not a concern, short enough to read in a log line.
const DIGEST_LENGTH: int = 16


static func of(scenario: Scenario) -> String:
	return state_string(scenario).sha256_text().substr(0, DIGEST_LENGTH)


## The digest's INPUT, before hashing. A mismatched digest says only THAT two runs differ — this
## says WHICH entity, which is the whole of a divergence hunt.
static func state_string(scenario: Scenario) -> String:
	var parts: PackedStringArray = []
	for commander: Commander in scenario.commanders:
		if commander == null:
			continue
		var entities: PackedStringArray = []
		for child: Node in commander.get_children():
			var entity := child as Commandable
			if entity == null or entity.is_queued_for_deletion():
				continue
			var hp: float = entity.defense.hp if entity.defense != null else 0.0
			var at: Vector3 = entity.global_position
			entities.append("%s@%.3f,%.3f,%.3f#%.2f" % [entity.id, at.x, at.y, at.z, hp])
		entities.sort()
		parts.append(
			(
				"c%d:e%d:d%d:%s"
				% [commander.id, commander.energy, commander.dominion, "|".join(entities)]
			)
		)
	return "|".join(parts)
