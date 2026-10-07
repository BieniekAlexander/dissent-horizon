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
## for the starting units and sanctions.
##
## REQUIRED — Scenario._validate_player_slots fails the boot when a slot leaves it
## null. There is no default: Commander.faction_scene is not exported precisely so
## that this is the only place a commander's faction can be configured.
@export var faction: PackedScene

## Bot difficulty (see Difficulty). Ignored for a human slot.
@export var difficulty: Difficulty = Difficulty.MEDIUM

#region Personality
## Which trained personality this bot plays, by its id in the roster (BotRoster,
## `resources/bots/roster.json`); "" plays the tier alone. The vector is applied on top of
## `difficulty`, which keeps the periods — a member plays as trained only at the tier it was
## trained at. An id the roster lacks fails the boot (Scenario._validate_player_slots).
@export var personality: String = ""

## Field-by-field overrides on top of the tier and personality, keyed by BotDifficulty field
## name — a one-off authored tweak ("this one never attacks") that does not deserve a roster
## entry. A key that names no field fails the boot.
@export var config_overrides: Dictionary = {}
#endregion

#region Simulation levers
## Set by a decision simulation only (gdd/systems/ai/decision-sims.md); never by a scene a
## player can reach. `omniscient` gives the commander no Fog, so it sees the whole map — the
## perception layer is the same code with a fog that hides nothing. The `consider_*` lists
## restrict what the bot may build or train so one decision is under test; empty means all.
var omniscient: bool = false
var consider_structures: Array[StringName] = []
var consider_units: Array[StringName] = []
#endregion

#region Starting resources
## The resource stockpiles the commander begins the match with. Scenario applies
## these to the built commander; a commander built without a slot (the neutral world
## commander) starts at zero.
@export var starting_energy: int = 1000
## Below every faction's cheapest sanction, and the same for every player: a head start on
## the first unlock, not a free one (gdd/systems/macroeconomics/pacing/sanction-calibration.md).
@export var starting_dominion: int = 100
#endregion

## The live Commander built for this slot, assigned by Scenario at build time.
## Runtime-only (not part of the authored resource).
var commander: Commander
