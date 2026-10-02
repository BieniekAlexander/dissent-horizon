class_name DebugRoster
extends RefCounted

## Every piece the debug spawner can place, and how its card lays them out. Read from the
## generated roster (SpecGenerators.debug_roster_json): one entry per unit, structure and
## feature, with its faction, scene and the producers that train it. Pure: the grouping is a
## function of the entries, so it is tested without a scene.
##
## See gdd/systems/ux/ui/debug-mode.md §The piece spawner.

const ROSTER_PATH: String = "res://resources/generated/debug_roster.json"

## The heading over a faction's fixtures, which lead the card.
const FIXTURES_TITLE: String = "Structures"
## The heading over units no structure trains.
const UNTRAINED_TITLE: String = "Not trained"


## The generated roster, or [] when it has not been generated.
static func load_entries() -> Array:
	if not FileAccess.file_exists(ROSTER_PATH):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROSTER_PATH))
	return parsed if parsed is Array else []


## Every faction some entry belongs to, sorted.
static func factions(entries: Array) -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in entries:
		var faction: String = entry["faction"]
		if not out.has(faction):
			out.append(faction)
	out.sort()
	return out


## The faction of the first of `scene_paths` that some entry's scene is, or "" when none is.
## How the card finds the player's faction: the roster's faction keys come from folder codes
## and doc paths, not from the Faction scenes' names, so matching by scene is what lines up.
static func faction_of_scenes(entries: Array, scene_paths: Array) -> String:
	var faction_by_scene: Dictionary = {}
	for entry: Dictionary in entries:
		faction_by_scene[entry["scene"]] = entry["faction"]
	for path: Variant in scene_paths:
		if faction_by_scene.has(path):
			return faction_by_scene[path]
	return ""


## `faction`'s entries as the card draws them: [{"title", "entries"}]. Fixtures first; then one
## group per producer, in the order producers are first met, titled with the producer's label;
## then the units nothing trains. A unit with several producers is under each of them. Empty
## groups are left out.
static func groups(entries: Array, faction: String) -> Array[Dictionary]:
	var labels: Dictionary = {}
	for entry: Dictionary in entries:
		labels[entry["id"]] = entry["label"]
	var fixtures: Array = []
	var untrained: Array = []
	var by_producer: Dictionary = {}
	for entry: Dictionary in entries:
		if entry["faction"] != faction:
			continue
		if entry["is_fixture"]:
			fixtures.append(entry)
		elif entry["producers"].is_empty():
			untrained.append(entry)
		for producer: String in [] if entry["is_fixture"] else entry["producers"]:
			if not by_producer.has(producer):
				by_producer[producer] = []
			by_producer[producer].append(entry)
	var out: Array[Dictionary] = []
	if not fixtures.is_empty():
		out.append({"title": FIXTURES_TITLE, "entries": fixtures})
	for producer: String in by_producer:
		out.append({"title": labels.get(producer, producer), "entries": by_producer[producer]})
	if not untrained.is_empty():
		out.append({"title": UNTRAINED_TITLE, "entries": untrained})
	return out
