class_name Faction extends Node

## A Faction defines what a commander has access to: its starting units and the set of
## commander-level Sanctions it may deploy. Its command centre is not a faction field: it is
## dropped at the start of a match (Deployment.COMMAND_CENTRE_SCENES). A Commander holds a single
## `faction` reference (instanced from its faction scene) and consults it for
## these things, so faction membership — not hardcoded lists — drives what shows
## up in the UI and what the player can use.
##
## Factions are authored entirely as scenes (e.g. anarchical.tscn): one concrete
## Faction node with its data filled in. There are no per-faction subclasses — a
## faction's sanctions are authored as a sanction GRID: SanctionUnlock resources in
## `sanction_unlocks`, each wrapping an Sanction with its dominion cost, the (tier,
## column) slot it occupies, and the single unlock (if any) whose family it continues.

## Display name for this faction.
@export var faction_name: String = ""

## The units a commander of this faction begins the match with. One entry per unit (repeat a
## scene to field several). Units only: the command centre arrives by drop.
## Consumed by Skirmish, which builds each player slot's opening force from its
## faction rather than from pre-placed scene-tree entities.
@export var starting_units: Array[PackedScene] = []

## How this faction's starting_units are arranged when they deploy: a scene whose Node3D
## children are the SLOTS, one per starting unit, laid out in the XZ plane facing −Z. Skirmish
## anchors it toward the middle of the map and rotates it to face that way — see
## [StartingFormation].
##
## The child count must EQUAL starting_units.size(); a mismatch is an authoring error, and
## Skirmish falls back to the old scatter rather than deploying half a formation. Null means
## no formation at all, which is that same scatter.
@export var starting_formation: PackedScene

## This faction's sanction grid: every SanctionUnlock cell. The layout lives on each
## unlock (its `tier` and `column`), so this array is a flat, unordered SET rather than a
## layout of its own — the HUD draws the grid from the slots. List every cell here,
## including ones reached only as a parent, so the set is closed. A commander turns this
## into per-match state via SanctionGrid (see Commander).
@export var sanction_unlocks: Array[SanctionUnlock] = []

## The piece id of this faction's DEDICATED infrastructure provider — the structure built for
## capacity alone. Its grant is the infrastructure bar's segment size, whether or not one stands
## (Commander.infrastructure_provider_grant). Empty for a faction with none; the bar then draws
## no segments.
@export var infrastructure_source: StringName = &""
