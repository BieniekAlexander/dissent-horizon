class_name UpgradeCatalog
extends RefCounted

## WHAT AN UPGRADE IS, read from resources/generated/upgrades.json (one entry per
## `kind: Upgrade` doc — see tools/spec_import).
##
## An upgrade is a ONE-TIME, COMMANDER-WIDE purchase researched at a structure: the structure
## lists it under `researches:`, it runs as an ordinary job in the global ProductionQueue, and
## finishing it adds its id to the commander's owned upgrades (Commander.complete_upgrade)
## rather than spawning anything. Losing the structure afterwards does not take it back.
##
## What an upgrade DOES is authored on its doc as `modifies:` entries, each naming a piece and
## one of its abilities and the value it overrides. Readers ask this class for the value in
## force for a caster (range_for), so an upgrade reaches pieces already on the field as well
## as future ones, with no per-unit state to keep in step.
##
## Why: gdd/systems/macroeconomics/upgrades.md.
##
## Read-only authored data, so a plain static table rather than a per-commander copy.

const UPGRADES_JSON_PATH: String = "res://resources/generated/upgrades.json"

## id -> {"title": String, "modifies": [{"piece", "ability", "range"}]}.
static var _entries: Dictionary = _load()


static func _load() -> Dictionary:
	var out: Dictionary = {}
	if not FileAccess.file_exists(UPGRADES_JSON_PATH):
		return out
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(UPGRADES_JSON_PATH))
	if parsed is Dictionary:
		for id: Variant in parsed:
			var entry: Variant = parsed[id]
			out[StringName(str(id))] = entry if entry is Dictionary else {}
	return out


## Whether `a_id` names an upgrade rather than a piece. Upgrades and pieces share the one spec
## namespace, so an id is never both.
static func is_upgrade(a_id: Variant) -> bool:
	return a_id != null and _entries.has(StringName(str(a_id)))


static func title_of(a_id: StringName) -> String:
	return str((_entries.get(a_id, {}) as Dictionary).get("title", String(a_id)))


## The reach of `a_ability` as `a_piece_id` casts it for `a_commander`: the longest `range`
## any owned upgrade authors for that piece and ability, or `a_base` when none does.
##
## The LONGEST rather than the latest: two upgrades extending one reach should never shorten
## it by being researched in the other order.
static func range_for(
	a_commander: Commander,
	a_piece_id: StringName,
	a_ability: StringName,
	a_base: float
) -> float:
	if a_commander == null:
		return a_base
	var best: float = a_base
	for upgrade_id: StringName in a_commander.owned_upgrades():
		for modifier: Variant in (_entries.get(upgrade_id, {}) as Dictionary).get("modifies", []):
			var m: Dictionary = modifier if modifier is Dictionary else {}
			if StringName(str(m.get("piece", ""))) != a_piece_id \
					or StringName(str(m.get("ability", ""))) != a_ability \
					or not m.has("range"):
				continue
			best = maxf(best, float(m["range"]))
	return best
