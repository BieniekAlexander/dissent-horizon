class_name BotRoster
extends RefCounted

## THE TRAINED PERSONALITIES A SCENARIO MAY NAME.
##
## A personality is a vector over BotDifficulty's searchable fields, found by the population
## search (tools/selfplay/train.py; gdd/systems/ai/bot-randomness.md §Strength is a search).
## The roster file is that search's export — `train.py export` writes it, nothing edits it by
## hand — and a `PlayerSlot.personality` names one of its members. The vector is applied on
## top of the SLOT's tier, so the tier still sets the periods (reaction time is the tier's
## identity, never searched); each member records the tier it was trained at, and plays as
## trained only there.
##
## Missing file: an empty roster. That is not an error here — a scenario that names nobody
## never needs it — and Scenario's slot validation is what reports a name that resolves to
## nothing, at boot, as authored content should be.

const DEFAULT_PATH: String = "res://resources/bots/roster.json"

## id → the member's document: at least `vector` (field → value) and `tier` (the name it was
## trained at); the rest is the search's bookkeeping and is ignored here.
var _members: Dictionary = {}


static func load_default() -> BotRoster:
	return BotRoster.load_from(DEFAULT_PATH)


static func load_from(path: String) -> BotRoster:
	if not FileAccess.file_exists(path):
		return BotRoster.new()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("%s is not a roster document" % path)
		return BotRoster.new()
	return BotRoster.from_dictionary(parsed)


static func from_dictionary(document: Dictionary) -> BotRoster:
	var roster := BotRoster.new()
	roster._members = document.get("members", {})
	return roster


func has(a_id: String) -> bool:
	return _members.has(a_id)


func ids() -> Array[String]:
	var out: Array[String] = []
	for key: Variant in _members:
		out.append(str(key))
	return out


func vector(a_id: String) -> Dictionary:
	return (_members.get(a_id, {}) as Dictionary).get("vector", {})


## The tier name the member was trained at, "" when unknown.
func trained_tier(a_id: String) -> String:
	return str((_members.get(a_id, {}) as Dictionary).get("tier", ""))


## Apply member `a_id`'s vector onto `a_config`. "" on success; a message, and the config
## untouched, when the id is unknown or its vector names a field that does not exist.
func apply(a_id: String, a_config: BotDifficulty) -> String:
	if not has(a_id):
		return "no personality '%s' in the roster" % a_id
	return a_config.apply_overrides(vector(a_id))
