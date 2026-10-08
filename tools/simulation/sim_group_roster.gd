class_name SimGroupRoster
extends RefCounted

## What a running spec actually placed: every group reference ("A.armyA") mapped to the
## entities spawned for it, plus the slot -> commander id assignment.
##
## The roster is the ONLY way orders and checks address entities. A group is a set the spec
## named, not a query over the world, so nothing here filters by commander the way a scenario
## [Condition] does — that difference is the whole reason the check vocabulary is separate
## from the Condition module (see simulation-tests.md §The check vocabulary).
##
## ENTRIES ARE HELD UNTYPED AND ARE ALLOWED TO BE FREED. A dead entity is a freed object, and
## Godot type-checks an Object argument against its declared class BEFORE the callee runs, so
## a freed instance cannot be passed to — or assigned to — anything typed `Entity`
## (CLAUDE.md §A freed object cannot be passed to a typed parameter). Every read therefore
## goes through a `Variant` and `is_instance_valid()` first. `member == null` is NOT that
## test: it is true for a freed object while `is_instance_valid` is false.
##
## EACH ENTRY REMEMBERS ITS PIECE ID, rather than asking the entity for it. A dead entity
## cannot be asked anything, so a piece-filtered count taken from live instances would shrink
## as the group took casualties — and "did all four riflemen die" would be unanswerable
## precisely when the answer is yes.

#region State
## "A.armyA" -> Array of { "entity": Variant (may be freed), "piece": String }, in
## declaration order.
var _members: Dictionary = {}
## slot name ("A") -> commander id (1, 2, …)
var _slot_ids: Dictionary = {}
## What the placed pieces fired, for the `hit_rate` check.
var shots: SimShotLog = SimShotLog.new()
#endregion


#region Building
func register_slot(a_slot: String, a_commander_id: int) -> void:
	_slot_ids[a_slot] = a_commander_id


func add(a_reference: String, a_entity: Actor, a_piece: String) -> void:
	if not _members.has(a_reference):
		_members[a_reference] = []
	(_members[a_reference] as Array).append(
		{"entity": a_entity, "piece": a_piece, "id": a_entity.get_instance_id()}
	)
	shots.watch(a_reference, a_entity, a_piece)


func has_group(a_reference: String) -> bool:
	return _members.has(a_reference)


func group_references() -> Array:
	return _members.keys()


func commander_id(a_slot: String) -> int:
	return int(_slot_ids.get(a_slot, -1))


## The slot a commander id belongs to, or "" — what the `owner` check compares against.
## The live commander a slot built, for the bot-state checks. Registered by SimArena once the
## scenario has built its commanders; null for a slot nobody registered.
var _commanders: Dictionary = {}  # slot -> Commander


func register_commander(a_slot: String, a_commander: Commander) -> void:
	_commanders[a_slot] = a_commander


## The thinking Bot behind `a_slot`, or null when the slot has no bot or its brain has not
## built its managers yet (the first think does that).
func bot_of(a_slot: String) -> Bot:
	var commander: Variant = _commanders.get(a_slot)
	if commander == null or not is_instance_valid(commander):
		return null
	return commander as Bot


## `a_slot`'s brain, or null.
func brain_of(a_slot: String) -> BotBrain:
	var bot: Bot = bot_of(a_slot)
	return bot.brain() if bot != null else null


func slot_of(a_commander_id: int) -> String:
	for slot: String in _slot_ids:
		if int(_slot_ids[slot]) == a_commander_id:
			return slot
	return ""


#endregion


#region Reading
## How many entities were spawned for this selection, alive or not. The denominator of
## "all of them died".
func spawned_count(a_reference: String, a_piece: String = "") -> int:
	var total: int = 0
	for entry: Dictionary in _entries(a_reference):
		if a_piece == "" or str(entry["piece"]) == a_piece:
			total += 1
	return total


## Living members of the selection, in declaration order.
##
## "Living" is `is_instance_valid` plus a positive hp where the entity has a [Defense] at
## all: an entity is freed on death, but `queue_free` is deferred, so for the rest of the
## tick it is still a valid instance reporting zero hp.
##
## A GARRISONED unit counts as living. It is off the scene tree, which looks exactly like
## death from the outside, and treating it as dead would make "the transport survived with
## its cargo" unaskable.
func living(a_reference: String, a_piece: String = "") -> Array:
	var result: Array = []
	for entry: Dictionary in _entries(a_reference):
		if a_piece != "" and str(entry["piece"]) != a_piece:
			continue
		var member: Variant = entry["entity"]
		if not is_instance_valid(member):
			continue
		var entity: Actor = member
		if entity.defense != null and entity.defense.hp <= 0.0:
			continue
		result.append(entity)
	return result


## Members of the selection that are gone — spawned minus living.
func dead_count(a_reference: String, a_piece: String = "") -> int:
	return spawned_count(a_reference, a_piece) - living(a_reference, a_piece).size()


## Mean XZ position of the living members, or null when none are left. Null means "there is
## no such place" — a real state a caller must handle, rather than a zero that would silently
## mean the arena's centre.
func centroid(a_reference: String, a_piece: String = "") -> Variant:
	var alive: Array = living(a_reference, a_piece)
	if alive.is_empty():
		return null
	var total: Vector3 = Vector3.ZERO
	for entity: Actor in alive:
		total += entity.global_position
	return total / float(alive.size())


## The instance ids of every piece ever placed in `a_reference`, dead ones included: how a
## shot that landed on a piece since destroyed is still known to have hit the group.
func member_ids(a_reference: String) -> Array:
	return _entries(a_reference).map(func(e: Dictionary) -> int: return e["id"])


#endregion


#region Internal
func _entries(a_reference: String) -> Array:
	return _members.get(a_reference, [])
#endregion
