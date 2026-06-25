class_name BotBlackboard
extends RefCounted

## BotBlackboard — the bot's persistent BELIEF about the enemy, fog-limited.
##
## Each think the bot folds in what it currently SEES (Bot.visible_enemies) and
## remembers it after losing sight, so decisions can use believed enemy positions
## and composition rather than only what's on screen this instant. Two retention
## rules (per the design):
##   • STRUCTURES persist indefinitely (they don't move). A structure belief is
##     dropped only when the bot regains vision of its last-known spot and the
##     structure is no longer there — i.e. verified destroyed on revisit, never by
##     omnisciently checking if the node was freed.
##   • UNITS expire BLACKBOARD_EXPIRATION seconds after their last sighting — an old
##     sighting goes stale because units move (or die) out of view.
##
## Every entry carries the entity's last-known world location.

## Seconds a unit belief survives without a fresh sighting before it lapses.
const BLACKBOARD_EXPIRATION: float = 180.0


## One remembered enemy entity.
class Entry:
	var instance_id: int
	var type: int                       # Entity.Type
	var is_structure: bool
	var last_known_location: Vector3
	var last_seen_time: float           # seconds (Bot.seconds_elapsed) of last sighting
	var entity: Commandable             # live ref; may become invalid (use is_instance_valid)


var _bot: Bot
var _entries: Dictionary = {}           # instance_id -> Entry


func _init(a_bot: Bot) -> void:
	_bot = a_bot


## Fold current vision into the belief, then age it out. Call once per think.
func update() -> void:
	var now: float = _bot.seconds_elapsed()

	# 1. Refresh / add an entry for every enemy currently in view.
	var visible_ids: Dictionary = {}
	for e: Commandable in _bot.visible_enemies():
		visible_ids[e.get_instance_id()] = true
		_upsert(e, now)

	# 2. Age out beliefs. Structures: drop only when we can see their spot and they
	#    aren't there (verified gone). Units: drop once the sighting is stale.
	for id: int in _entries.keys():
		var entry: Entry = _entries[id]
		if entry.is_structure:
			if not visible_ids.has(id) and _bot.has_vision_at(entry.last_known_location):
				_entries.erase(id)
		elif now - entry.last_seen_time > BLACKBOARD_EXPIRATION:
			_entries.erase(id)


## All believed enemy entities (persistent structures + unexpired units).
func believed() -> Array:
	return _entries.values()

## Believed enemy structures (last-known locations; persist until verified gone).
func believed_structures() -> Array:
	return _entries.values().filter(func(e: Entry): return e.is_structure)

## Believed enemy units (last-known locations; expire after BLACKBOARD_EXPIRATION).
func believed_units() -> Array:
	return _entries.values().filter(func(e: Entry): return not e.is_structure)


func _upsert(e: Commandable, now: float) -> void:
	var id: int = e.get_instance_id()
	var entry: Entry = _entries.get(id)
	if entry == null:
		entry = Entry.new()
		entry.instance_id = id
		entry.type = e.type
		entry.is_structure = e.has_node("Structure")
		_entries[id] = entry
	entry.entity = e
	entry.last_known_location = e.global_position
	entry.last_seen_time = now
