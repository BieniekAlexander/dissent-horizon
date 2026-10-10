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
#endregion

#region Properties
## True: the person at the keyboard plays slot 1. False: every slot is a bot and they watch.
var human_plays_first_slot: bool = true
## One per player, in slot order: {"faction": scene path or RANDOM, "team": 0 … NUM_TEAMS,
## "difficulty": PlayerSlot.Difficulty — ignored while the slot is the player's}.
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
		_slots.append({"faction": RANDOM, "team": NO_TEAM, "difficulty": DEFAULT_DIFFICULTY})
	_slots.resize(count)


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


## Whether slot `a_slot` is a bot: every slot but the first, and the first when unticked.
func is_bot(a_slot: int) -> bool:
	return a_slot > 0 or not human_plays_first_slot


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
