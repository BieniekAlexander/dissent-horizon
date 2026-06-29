class_name PlayerSlot extends Resource

## One participant in a scenario: a single Commander, the faction it fields, and —
## for a bot — its difficulty. Scenario builds the Commander for each slot (a Bot or
## the human player.tscn rig) and stores it back on `commander`.
##
## The neutral world commander (id 0) is NOT a slot; slots map to commander ids
## 1..N in array order. Replaces Scenario's old commander_count / human_commander_id
## / passive_bot_ids configuration.

## Difficulty tiers for a bot slot. Only PASSIVE currently changes behaviour — it
## disables the BotBrain think loop. The rest are stored (propagated to the brain)
## for future tuning but behave identically for now. Ignored for a human slot.
enum Difficulty {
	PASSIVE = 0,
	EASY = 1,
	MEDIUM = 2,
	HARD = 3,
	IMPOSSIBLE = 4,
}

## True → an AI-controlled Bot; false → the human player (the player.tscn rig).
@export var is_bot: bool = true

## The faction this player fields, as a faction scene (e.g. anarchical.tscn).
## Propagated to the built Commander (sets its faction_scene), which instances it
## for the starting structure and ordnances. When null, the commander keeps its own
## default faction (e.g. the one player.tscn ships with).
@export var faction: PackedScene

## Bot difficulty (see Difficulty). Ignored for a human slot.
@export var difficulty: Difficulty = Difficulty.MEDIUM

#region Starting resources
## The resource stockpiles the commander begins the match with. Scenario applies
## these to the built commander; a commander built without a slot (the neutral world
## commander) starts at zero.
@export var starting_ore: int = 1000
@export var starting_dominion: int = 1000
#endregion

## The live Commander built for this slot, assigned by Scenario at build time.
## Runtime-only (not part of the authored resource).
var commander: Commander
