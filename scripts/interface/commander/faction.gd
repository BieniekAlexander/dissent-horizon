class_name Faction extends Node

## A Faction defines what a commander has access to: its starting structure and
## the set of commander-level Ordnances it may deploy. A Commander holds a single
## `faction` reference (instanced from its faction scene) and consults it for
## these things, so faction membership — not hardcoded lists — drives what shows
## up in the UI and what the player can use.
##
## Factions are authored entirely as scenes (e.g. anarchical.tscn): one concrete
## Faction node with its data filled in. There are no per-faction subclasses — a
## faction's ordnances are authored as an ordnance DAG: OrdnanceUnlock resources in
## `ordnance_unlocks`, each wrapping an Ordnance with its dominion cost and the
## prerequisites that gate it.

## Display name for this faction.
@export var faction_name: String = ""

## The structure a commander of this faction begins the match with.
@export var starting_structure: PackedScene

## The units a commander of this faction begins the match with, deployed around
## the starting structure. One entry per unit (repeat a scene to field several).
## Consumed by Skirmish, which builds each player slot's opening force from its
## faction rather than from pre-placed scene-tree entities.
@export var starting_units: Array[PackedScene] = []

## This faction's ordnance DAG: every OrdnanceUnlock node, in display order. The
## edges live on each unlock (its `prerequisites`); list every node here, including
## ones reached only as a prerequisite, so the set is closed. A commander turns this
## into per-match state via OrdnanceArsenal (see Commander).
@export var ordnance_unlocks: Array[OrdnanceUnlock] = []
