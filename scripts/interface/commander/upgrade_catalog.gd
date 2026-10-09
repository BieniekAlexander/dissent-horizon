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
## What an upgrade DOES is authored on its doc as `modifies:` entries, each naming WHICH pieces
## (a `piece` id, or every unit of a `frame`), optionally one of their abilities, and one effect:
## an ability's `range`, a factor on hit points, on rearm speed or on an ability's recharge
## speed, or `unlocks` — the piece may not use that ability until the upgrade is owned. Readers
## ask this class for the value in force (range_for, factor_for, is_ability_unlocked), so an
## upgrade reaches pieces already on the field as well as future ones.
##
## Why: gdd/systems/macroeconomics/upgrades.md.
##
## Read-only authored data, so a plain static table rather than a per-commander copy.

const UPGRADES_JSON_PATH: String = "res://resources/generated/upgrades.json"

## The multiplicative effects a modifier may carry. Each is a FACTOR on a rate or an amount:
## 2.0 rearms twice as fast, 1.25 has a quarter more hit points.
const HP_FACTOR: StringName = &"hp_factor"
const REARM_RATE_FACTOR: StringName = &"rearm_rate_factor"
const COOLDOWN_RATE_FACTOR: StringName = &"cooldown_rate_factor"

## id -> {"title": String, "faction": String, "modifies": [{"piece" | "frame", "ability"?,
## <one effect key>}]}.
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


## Every upgrade whose doc names `a_faction` first in `ui.factions` (the faction key the debug
## roster uses), sorted by title.
static func ids_of_faction(a_faction: String) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _entries:
		if str((_entries[id] as Dictionary).get("faction", "")) == a_faction:
			out.append(id)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return title_of(a) < title_of(b))
	return out


## The upgrade's `modifies:` entries, each a Dictionary with a selector (`piece` or `frame`),
## an optional `ability`, and one effect key. Empty for an unknown id.
static func modifiers_of(a_id: StringName) -> Array:
	var out: Array = []
	for modifier: Variant in (_entries.get(a_id, {}) as Dictionary).get("modifies", []):
		if modifier is Dictionary:
			out.append(modifier)
	return out


## The reach of `a_ability` as `a_piece_id` casts it for `a_commander`: the longest `range`
## any owned upgrade authors for that piece and ability, or `a_base` when none does.
##
## The LONGEST rather than the latest: two upgrades extending one reach should never shorten
## it by being researched in the other order.
static func range_for(
	a_commander: Commander, a_piece_id: StringName, a_ability: StringName, a_base: float
) -> float:
	if a_commander == null:
		return a_base
	var best: float = a_base
	for upgrade_id: StringName in a_commander.owned_upgrades():
		for modifier: Variant in (_entries.get(upgrade_id, {}) as Dictionary).get("modifies", []):
			var m: Dictionary = modifier if modifier is Dictionary else {}
			if (
				StringName(str(m.get("piece", ""))) != a_piece_id
				or StringName(str(m.get("ability", ""))) != a_ability
				or not m.has("range")
			):
				continue
			best = maxf(best, float(m["range"]))
	return best


## The product of every `a_key` factor `a_piece`'s commander owns that applies to it — and, for
## an ability-scoped factor, to `a_ability`. 1.0 when none does.
##
## A PRODUCT, so two owned upgrades raising one value stack, in either order. An upgrade applies
## to whatever its commander fields, captured pieces of another faction included.
static func factor_for(a_piece: Entity, a_key: StringName, a_ability: StringName = &"") -> float:
	if a_piece == null or a_piece.commander == null:
		return 1.0
	var factor: float = 1.0
	for upgrade_id: StringName in a_piece.commander.owned_upgrades():
		for modifier: Variant in (_entries.get(upgrade_id, {}) as Dictionary).get("modifies", []):
			var m: Dictionary = modifier if modifier is Dictionary else {}
			if (
				m.has(a_key)
				and StringName(str(m.get("ability", ""))) == a_ability
				and applies_to(m, a_piece)
			):
				factor *= float(m[a_key])
	return factor


## Whether `a_piece` may use `a_ability` as far as research goes: true unless some upgrade
## `unlocks` that ability for this piece and its commander owns none of them. One owned gate is
## enough when several upgrades name the same one.
##
## PERMISSION, not capability: the piece's `Abilities` pool still grants the ability, which is
## what keeps the button on its card (drawn LOCKED) rather than absent until the research.
static func is_ability_unlocked(a_piece: Entity, a_ability: StringName) -> bool:
	if a_piece == null:
		return true
	var gates: Array[StringName] = upgrades_unlocking(a_piece.id, a_ability)
	if gates.is_empty():
		return true
	if a_piece.ownership == null or a_piece.commander == null:
		return false
	var commander: Commander = a_piece.commander
	return gates.any(func(id: StringName) -> bool: return commander.has_upgrade(id))


## Every upgrade that `unlocks` `a_ability` for the piece `a_piece_id`, in table order.
static func upgrades_unlocking(a_piece_id: StringName, a_ability: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for upgrade_id: StringName in _entries:
		for modifier: Variant in (_entries[upgrade_id] as Dictionary).get("modifies", []):
			var m: Dictionary = modifier if modifier is Dictionary else {}
			if (
				m.get("unlocks", false)
				and StringName(str(m.get("piece", ""))) == a_piece_id
				and StringName(str(m.get("ability", ""))) == a_ability
			):
				out.append(upgrade_id)
	return out


## Whether a modifier's selector picks `a_piece`: its `piece` id, or — for a `frame` selector —
## any UNIT of that frame. A frame selector leaves structures alone: "every BIO unit" is what
## one says, and a structure is never what a frame-wide upgrade is bought for.
static func applies_to(a_modifier: Dictionary, a_piece: Entity) -> bool:
	if a_modifier.has("piece"):
		return StringName(str(a_modifier["piece"])) == a_piece.id
	if not a_modifier.has("frame") or a_piece.defense == null or not a_piece.is_in_group("unit"):
		return false
	return str(a_modifier["frame"]) == Defense.FrameType.keys()[a_piece.defense.frame_type]
