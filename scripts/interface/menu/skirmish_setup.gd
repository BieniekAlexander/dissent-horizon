class_name SkirmishSetup
extends RefCounted
## WHAT THE SKIRMISH LOBBY HAS SET: how many players, each one's faction (or Random) and team,
## and whether the person at the keyboard plays the first slot or watches every slot as a bot.
## The lobby (SkirmishLobby) draws this and edits it; nothing here knows about controls.
##
## `recipe()` freezes the choices into the dictionary SkirmishLauncher builds a match from —
## Random resolved to a real faction, seeds drawn — and that same dictionary is what a replay
## of the match stores, so playback rebuilds the identical match.
## gdd/systems/ux/ui/menus.md §Skirmish.

#region Constants
const MIN_PLAYERS: int = 2
const MAX_PLAYERS: int = Commander.NUM_MAX_COMMANDERS
## A slot's faction when the lobby leaves it to chance.
const RANDOM: String = ""
## The factions a skirmish offers, by scene. Only the two whose rosters, sanctions and bots are
## complete; Libertarian and Technocratic have a command centre but no sanction grid yet.
## TODO: add them as they are finished (gdd/tasks.md T-103).
const FACTIONS: Array[String] = [
	"res://scenes/factions/anarchical.tscn",
	"res://scenes/factions/colonial.tscn",
]
## A new bot slot's difficulty: what every lobby bot played at before the dropdown existed.
const DEFAULT_DIFFICULTY: PlayerSlot.Difficulty = PlayerSlot.Difficulty.HARD
## No team: the slot is an alliance of its own (PlayerSlot.alliance 0).
const NO_TEAM: int = 0
## In a networked lobby, the host's peer id; it always plays the first slot.
const HOST_PEER: int = 1
#endregion

#region Properties
## True: the person at the keyboard plays slot 1. False: every slot is a bot and they watch.
## Always true in a networked lobby, whose host plays slot 1.
var human_plays_first_slot: bool = true
## A networked lobby: the host marks slots OPEN for other players, who are seated in them
## (gdd/systems/commands/netplay.md §Decisions, entry).
var is_networked: bool = false:
	set(v):
		is_networked = v
		if v:
			human_plays_first_slot = true
## Slot -> the peer seated in it, for every seated OPEN slot (the host's own first slot is
## implicit). Networked only.
var _seats: Dictionary = {}
## One per player, in slot order: {"faction": scene path or RANDOM, "team": 0 … NUM_TEAMS,
## "difficulty": PlayerSlot.Difficulty — ignored while the slot is a person's, "open": a slot
## another player may take, networked only}.
var _slots: Array[Dictionary] = []
#endregion


#region Lifecycle
func _init(a_players: int = MIN_PLAYERS) -> void:
	set_player_count(a_players)


#endregion


#region Public API
func player_count() -> int:
	return _slots.size()


## Grow or shrink to `a_count` players, clamped to MIN_PLAYERS … MAX_PLAYERS. Slots already set
## keep their choices; new ones start Random and teamless.
func set_player_count(a_count: int) -> void:
	var count: int = clampi(a_count, MIN_PLAYERS, MAX_PLAYERS)
	while _slots.size() < count:
		_slots.append(
			{"faction": RANDOM, "team": NO_TEAM, "difficulty": DEFAULT_DIFFICULTY, "open": false}
		)
	_slots.resize(count)
	for slot: int in _seats.keys():
		if slot >= count:
			_seats.erase(slot)


func faction_of(a_slot: int) -> String:
	return str(_slots[a_slot]["faction"])


## Set slot `a_slot`'s faction to a scene in FACTIONS, or RANDOM. Anything else is ignored.
func set_faction(a_slot: int, a_faction: String) -> void:
	if a_slot < 0 or a_slot >= _slots.size():
		return
	if a_faction != RANDOM and not FACTIONS.has(a_faction):
		return
	_slots[a_slot]["faction"] = a_faction


func difficulty_of(a_slot: int) -> PlayerSlot.Difficulty:
	return _slots[a_slot]["difficulty"]


## Set slot `a_slot`'s bot difficulty. Kept while the slot is the player's, for when it is not.
func set_difficulty(a_slot: int, a_difficulty: PlayerSlot.Difficulty) -> void:
	if a_slot < 0 or a_slot >= _slots.size():
		return
	if not PlayerSlot.Difficulty.values().has(a_difficulty):
		return
	_slots[a_slot]["difficulty"] = a_difficulty


## Whether slot `a_slot` is a bot: the first only when unticked, any other unless OPEN.
func is_bot(a_slot: int) -> bool:
	if a_slot == 0:
		return not human_plays_first_slot
	return not is_open(a_slot)


#region Networked seats
## Whether slot `a_slot` is OPEN: a person's, taken by whoever is seated there.
func is_open(a_slot: int) -> bool:
	return is_networked and a_slot > 0 and a_slot < _slots.size() and bool(_slots[a_slot]["open"])


## Open or close slot `a_slot` (never the host's first). Closing it unseats whoever sat there.
func set_open(a_slot: int, a_is_open: bool) -> void:
	if not is_networked or a_slot <= 0 or a_slot >= _slots.size():
		return
	_slots[a_slot]["open"] = a_is_open
	if not a_is_open:
		_seats.erase(a_slot)


## The peer seated in slot `a_slot`: the host for the first slot, 0 for nobody.
func peer_in(a_slot: int) -> int:
	if a_slot == 0:
		return HOST_PEER if is_networked else 0
	return int(_seats.get(a_slot, 0))


## The slot `a_peer` is seated in, or -1.
func slot_of(a_peer: int) -> int:
	if a_peer == HOST_PEER and is_networked:
		return 0
	for slot: int in _seats:
		if int(_seats[slot]) == a_peer:
			return slot
	return -1


## Seat `a_peer` in OPEN slot `a_slot`, leaving any slot it held. Refused, returning false, for a
## slot that is not open or is taken by someone else.
func seat(a_peer: int, a_slot: int) -> bool:
	if not is_open(a_slot) or (peer_in(a_slot) != 0 and peer_in(a_slot) != a_peer):
		return false
	unseat(a_peer)
	_seats[a_slot] = a_peer
	return true


## Seat `a_peer` in the first free OPEN slot; the slot, or -1 when none is free.
func seat_anywhere(a_peer: int) -> int:
	for slot: int in range(1, _slots.size()):
		if is_open(slot) and peer_in(slot) == 0:
			seat(a_peer, slot)
			return slot
	return -1


func unseat(a_peer: int) -> void:
	var slot: int = slot_of(a_peer)
	if slot > 0:
		_seats.erase(slot)


## Every seated peer -> the commander it plays (slot + 1), the host's included: what the match
## seats each machine in (NetSession.offer_match).
func match_seats() -> Dictionary:
	var out: Dictionary = {}
	for slot: int in _slots.size():
		if peer_in(slot) != 0:
			out[peer_in(slot)] = slot + 1
	return out


## The setup as a plain dictionary — what the host sends every peer in the lobby.
func to_dict() -> Dictionary:
	var seats: Array = []
	for slot: int in _seats:
		seats.append([slot, int(_seats[slot])])
	return {
		"slots": _slots.duplicate(true),
		"first_human": human_plays_first_slot,
		"networked": is_networked,
		"seats": seats,
	}


## The setup `a_dict` (from to_dict) describes; JSON's floats are read back as ints.
static func from_dict(a_dict: Dictionary) -> SkirmishSetup:
	var setup := SkirmishSetup.new()
	var slots: Array = a_dict.get("slots", [])
	setup.set_player_count(slots.size())
	setup.is_networked = bool(a_dict.get("networked", false))
	setup.human_plays_first_slot = bool(a_dict.get("first_human", true))
	for i: int in mini(slots.size(), setup.player_count()):
		var slot: Dictionary = slots[i]
		setup.set_faction(i, str(slot.get("faction", RANDOM)))
		setup.set_team(i, int(slot.get("team", NO_TEAM)))
		setup.set_difficulty(
			i, int(slot.get("difficulty", DEFAULT_DIFFICULTY)) as PlayerSlot.Difficulty
		)
		setup.set_open(i, bool(slot.get("open", false)))
	for pair: Variant in a_dict.get("seats", []):
		setup.seat(int(pair[1]), int(pair[0]))
	return setup


#endregion


func team_of(a_slot: int) -> int:
	return int(_slots[a_slot]["team"])


## Set slot `a_slot`'s team: NO_TEAM, or 1 … PlayerSlot.NUM_TEAMS.
func set_team(a_slot: int, a_team: int) -> void:
	if a_slot < 0 or a_slot >= _slots.size():
		return
	_slots[a_slot]["team"] = clampi(a_team, NO_TEAM, PlayerSlot.NUM_TEAMS)


## Each slot's alliance index, in slot order — the same numbering the match will use
## (Scenario.alliance_indices): teamless slots each their own, teammates one between them.
func alliance_indices() -> PackedInt32Array:
	var slots: Array = []
	for slot: Dictionary in _slots:
		var player := PlayerSlot.new()
		player.alliance = int(slot["team"])
		slots.append(player)
	return Scenario.alliance_indices(slots)


## Why this setup cannot be played, in words for the lobby; empty when it can.
func problems() -> PackedStringArray:
	var out := PackedStringArray()
	var alliances: Dictionary = {}
	for index: int in alliance_indices():
		alliances[index] = true
	if alliances.size() < 2:
		out.append("Everyone is on one team: put at least one player on another.")
	for slot: int in _slots.size():
		if is_open(slot) and peer_in(slot) == 0:
			out.append("Player %d's slot is open, and nobody has taken it yet." % (slot + 1))
	return out


func can_play() -> bool:
	return problems().is_empty()


## Freeze the choices into a recipe for SkirmishLauncher: Random resolved, seeds drawn from
## `a_rng`. Same rng state, same recipe.
func recipe(a_rng: RandomNumberGenerator) -> Dictionary:
	var players: Array = []
	for i: int in _slots.size():
		var faction: String = faction_of(i)
		if faction == RANDOM:
			faction = FACTIONS[a_rng.randi_range(0, FACTIONS.size() - 1)]
		(
			players
			. append(
				{
					"faction": faction,
					"team": team_of(i),
					"is_bot": is_bot(i),
					"difficulty": int(difficulty_of(i)),
				}
			)
		)
	return {
		"version": SkirmishLauncher.RECIPE_VERSION,
		"players": players,
		"map_seed": a_rng.randi(),
		"rng_seed": a_rng.randi(),
	}


## A faction scene's player-facing name (Faction.faction_name), or "Random" for RANDOM.
static func faction_title(a_faction: String) -> String:
	if a_faction == RANDOM:
		return "Random"
	if not _faction_titles.has(a_faction):
		var root: Node = (load(a_faction) as PackedScene).instantiate()
		var faction := root as Faction
		_faction_titles[a_faction] = (
			faction.faction_name
			if faction != null and faction.faction_name != ""
			else a_faction.get_file().get_basename()
		)
		root.free()
	return _faction_titles[a_faction]


static var _faction_titles: Dictionary = {}
#endregion
