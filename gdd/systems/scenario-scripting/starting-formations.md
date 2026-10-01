---
title: Starting formations
---

# Starting formations

How a `Skirmish` deploys a faction's opening force: **three tiles toward the middle of the
map, in an authored arrangement, turned to face that way.**

It lives under scenario scripting because a `Skirmish` *is* a `Scenario` — one whose forces
are built at runtime from each slot's faction rather than placed in the scene by hand. The
map author places the start points; the faction says what stands on them.

## What it replaced

Units were scattered around the starting structure by `Map.add_entities`, which seeds its
search at a footprint-adjacent cell and grows outward. Two things were wrong with that as a
*starting* arrangement:

- **The direction was nobody's choice.** The seed is whichever adjacent cell happened to be
  nearest, so the opening force appeared on an arbitrary side of the base — in practice due
  north of it, which on a four-corner map means one player's army starts facing its own back
  wall and another's starts already pointed at the enemy.
- **The shape was nobody's choice either.** A scatter is a blob, and the piece the player
  most wants at the front (a Warlord, a Stock Truck) is as likely to be at the back of it.

Scattering is still exactly right for everything else that spawns a batch — a dropship's
payload, a wave event — and is still what happens when a faction declares no formation.

## The three decisions, and where each lives

**1. WHICH WAY — toward the play area's centre.** `Map.play_area()`, not the raw heightmap:
the heightmap's centre is the middle of a square that includes the four dead corners the play
rectangle excludes, and on a screen-aligned map those are large. A start point sitting exactly
on the centre names no direction at all; the authored facing then stands, which reproduces the
old due-north deployment for the one case with no better answer.

**2. HOW FAR — three tiles, measured in `Map.CELL_SIZE`.** Stated in CELLS rather than world
units so "three tiles" survives a change to what a tile is worth. Far enough to clear a
structure's footprint and its build-site clutter, near enough that the force reads as
belonging to that base.

**3. WHAT SHAPE — an authored scene of `Node3D` slots.** One child per starting unit, in
child order, laid out in the XZ plane. The scene is authored **facing −Z** (up-screen, and
Godot's own forward), so a slot with a negative Z is in front — between the base and the
middle of the map. Every offset is then rotated through the angle carrying that authored
facing onto the real heading, which is rigid: distances and neighbours are preserved, so a
formation with its leader in front keeps its leader in front from any corner of the map.

`Faction.starting_formation` holds the scene. `StartingFormation` is the geometry, and is
pure — no map, no navmesh, no scene tree — which is what makes all of it testable
(`tests/test_StartingFormation.gd`).

## The slot count must equal the unit count

A formation with the wrong number of slots is an **authoring error**, and it is reported
twice: an `assert`, so a debug run stops at the fault with the faction named, and a
`push_error` plus a fall back to the scatter, so a release build deploys a usable force
rather than none. Deploying a partial formation — some units placed, the rest dropped or
piled on the last slot — is the one outcome worth ruling out, because it looks like a
gameplay bug rather than a missing scene.

`tests/test_StartingFormation.gd` makes the same assertion against every shipped faction, so
a mismatch fails the suite rather than a match.

## At the edges

**The anchor only ever moves inward.** It is the start point plus three tiles *along the
heading toward the centre*, so a base in a corner deploys its force further into the map than
the base itself — never further out. That is the whole of the edge handling, and it is why no
clamp against the play rectangle is needed for the anchor.

**Individual slots are not clamped, they are snapped.** A formation is a couple of tiles
wide, so a slot can still land on a cliff, inside a footprint, or (on a tight map) outside the
play rectangle. `Map.add_entities` puts every placement point — authored or scattered —
through `nearest_navmesh_point`, so such a slot is corrected to the nearest navigable ground
rather than obeyed. One mechanism handles it for both paths.

The pitfall accepted: two slots snapping to the same corrected point will overlap on spawn,
where the scatter path would have spread them. It resolves itself within a tick or two of RVO,
and the alternative — re-running the non-overlapping search over the corrected points — would
throw away the arrangement that was the point of authoring one.

## Start points

A slot's start is an instance of `scenes/scenarios/start_point.tscn` (`StartPoint`, in
`Skirmish.START_POINT_GROUP`): a marker drawing a cylinder column (radius 2.5, height 10) in its
own colour, so starts read at a glance while a map is authored or reviewed. A new instance
picks a random colour the first time the editor shows it, and saving keeps it; the map
generator writes one per start. **The column is hidden in a running game** — the slot's
starting units stand on that spot.

**Start points belong to the MAP, not the scenario**: where a match can start is a fact about
the ground, so they sit inside the `Map` node and travel with a map scene
([map-generation.md](../terrain-and-navigation/map-generation.md) §Interface). A scenario may
have no more slots than its map has start points; with fewer, the slots take the first N by
sorted name and the map's remaining starts go unplayed — which is how one map serves a
two-player match and a four-player one.

## Deferred deployment — the command-centre drop

Decided 2026-09-28. This superseded **starting extractors** (a row of sites with extractors
already built, laid behind the starting structure by the start loader).

**Every Skirmish deploys this way, and it is the reference for tuning the competitive game.**
The stage is gated per SCENARIO (`Scenario.uses_deferred_deployment`, which `Skirmish` turns on)
because most campaign missions place their bases by authoring and do not use it. A slot's drops
are its commander's `Deployment`; the player's HUD and the bot land them through the same call.

**A slot starts with units and no base.** Its starting units deploy at the start point as now.
The slot also holds a one-time **ordnance** that drops the faction's command centre, almost
instantly, anywhere the player chooses.

**A faction doc's `starts_with:` lists units only.** The command centre and the two extractors
are not starting pieces a faction picks: they are what every deployment is, so which command
centre each faction drops is fixed in `Deployment` itself, and the importer refuses a structure
in `starts_with`. A faction with no entry there cannot deploy by drop. Scouting for a spot costs what the
slot would have earned meanwhile — that is the whole trade.

- **No income before the drop.** The starting bank is granted when the command centre lands,
  not at match start.
- **Then two extractor drops.** Once the command centre is down, the slot holds two more free
  ordnances, each dropping an extractor that brings its own extraction site with it. The
  command centre must be dropped first. An extractor drop may not land on an extraction site
  or a lithium pond — the free extractors never claim a map deposit.
- **Where a drop may land.** Inside the slot's current vision, on a valid footprint, and never
  onto another commander's units. There is no minimum distance from the enemy. An extractor
  drop's footprint is its site's.
  TODO: the no-units rule is meant to be shared by every building-drop ordnance, but only the
  deployment drops apply it — no other ordnance puts down a building yet.
- **The win condition waits for the drop.** While a slot still holds its command-centre
  ordnance, it cannot lose by losing its command centres. It loses instead if every one of its
  units dies before the drop. This is the existing two-latch elimination rule unchanged — the
  base half is armed only once a base exists — and the self-play harness applies the same pair.
- **No deadline.** The game never forces the drop. The CPU commander may keep an internal
  deadline of its own.
- **Starting units may fight before the drop.** `start_separation` is what keeps that rare.

**Spawn points are not known to anyone.** Each start is generated inside a guaranteed distance
band from a shelter, and every shelter's position is shown, fogged, from match start — so a
player can infer the opponent started in a ring around one of the shelters not near them.
→ [map-generation.md](../terrain-and-navigation/map-generation.md) §3 Shelters.

### Presentation and targeting

Decided 2026-09-28.

- **A dedicated deployment panel, not the ability bar or the ORDNANCE card.** The drops are
  cast by the COMMANDER, with no caster to find, and each is gone for the rest of the match once
  spent — so neither the ORDNANCE card's caster-finding path nor its "every ordnance, always"
  rule fits them. The panel exists only until its last drop is spent. The extractor drops show,
  disabled, until the command centre is down.
  PLANNED: the panel is to frame the opening phase visually; today it is plain buttons.
- **The economy bars are hidden until the command centre lands.** There is no readout of income
  forgone. PLANNED: their entrance is to be animated.
- **Targeting is the build ghost's**: right-click places, left-click cancels, as every armed
  order. EVERY cell of the footprint must be in the slot's current vision.
- **Units in the way.** The slot's OWN units on the footprint are moved off it; any other
  commander's units on it make the spot invalid.
- **The structure is in play the instant the drop is issued.** Its model descends onto the spot
  over 2 seconds, decelerating — presentation only; nothing about the structure waits for it.
- **What an ordnance creates is selected**, unless `modifier_additive` was held when it was
  issued. This is a general ordnance rule, not a deployment one.
  TODO: only the deployment drops apply it; no other ordnance creates actors yet.
- **`modifier_additive` keeps a drop armed only while it has a charge left.** With two
  extractor drops, the first placement held additively leaves the drop armed for the second;
  the second placement disarms it however it was issued. The rule generalises: the modifier
  never keeps a tool armed that cannot be used again.
  TODO: only the deployment drops apply the generalised rule; other armed tools do not check it.
- **No global cue.** An opponent learns of a drop only by having vision of it.
- **Hotkeys:** `deploy_command_centre` (F5) and `deploy_extractor` (F6), picked as unbound
  placeholders.
- **The CPU commander drops within 60 seconds.** An internal deadline of the bot's; the game
  itself imposes none. It scores the spots it can see with its building-placement score
  ([bot-architecture](../ai/bot-architecture.md) §Where a building goes) while its units scout,
  and drops once a spot clears a threshold that relaxes linearly from the score's ideal to its
  worst over the 60 seconds, so by the deadline the best spot seen so far is taken. Its
  extractors follow at once, ranked around the command centre (`BotDeployment`).
- **Shelter markers** on the minimap are out of scope for this work.

## Shipped formations

`scenes/factions/formations/`, named by shape and size and shared across factions:
`single`, `pair`, `wedge_3`, `wedge_4`. A wedge puts the faction's FIRST starting unit at the
point, which is the leader where a roster has one (the Warlord). The Colonial roster is three
Servants, so its point is just the first of them.
