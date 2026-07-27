---
title: The ability module fold
type: system-note
---

# The ability module fold

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

**There is ONE ability system.** A `kind: AbilityDefinition` doc defines what an ability IS, an
`Abilities` pool on a piece says who can use it and out of what charges, and
`AbilityCatalog` is how the game reads either at runtime. Nothing else grants an ability, and
nothing else counts a charge.

That is now true without exception. It was not, three times over, and each exception was a
whole parallel mechanism serving one or two pieces.

| retired | was | now |
| --- | --- | --- |
| `Bombards` | a component holding a cooldown and a projectile scene | an ability with a per-use `emits:` |
| `Ability.Type` + `Inventory` + `ToolSpec` | an enum with one live member, an inventory of charge slots, and a per-commander payload registry | `abilities:` pools granting `irradiate` |
| `Spotter` | a marker component whose presence was the capability | an ability granting `spot` |

## What the fold has to preserve, and what it necessarily changes

**Charges are the thing to be careful with.** `ToolSpec` and an `Abilities` pool are the same
idea with different defaults — `ToolSpec` gave 3 charges reloading one every 90 ticks — so the
fold RE-AUTHORS every charge it touches, and the authored pool has to reproduce the old
numbers deliberately rather than by luck. The three pieces that carry Radiate
([[tc_bioLight_antiMech]], [[an_aircraftLight_antiMech]], [[cl_bioLight_antiLight]]) are
authored `max_charges: 3, cooldown: 3` for exactly that reason.

**Spot gained a pool it did not have**, because every ability has one — "the charge is the
universal unit" and there is deliberately no way to express an ability that is not
charge-based. It is authored `max_charges: 1, cooldown: 1`, which is one tick: "no cooldown",
spelled in the one vocabulary rather than as a second concept meaning the same thing.

**Two numbers stayed constants.** `Spot.TARGET_RANGE` and `Spot.CHANNEL_TICKS` moved from the
component onto the command, not into the schema. Exactly one piece in the game spots, and a
value that never varies is not a configuration — exporting it makes the inspector claim a
choice nobody makes and the doc schema govern a number with one possible value. They become a
`spotting:` mapping on the day a second, longer-ranged spotter exists.

**`Commander.technology_mapping` is piece keys only again.** It used to carry int
`Ability.Type` values beside its StringName piece ids, as the gate for the one hard-coded
ability, plus a parallel `Ability.Type -> PackedScene` payload map. Both are gone: a granted
pool is the whole permission, and `AbilityCatalog.emission_of` is the whole payload.

## Retired keys are refused, never ignored

`bombards:` and `spotting:` are in `Schema.RETIRED`, so a doc still naming one is a hard error
that names its replacement. That is the rule for every retired key and it matters most here: a
doc setting `spotting: true` believes it is configuring something, and silently ignoring it
would leave a piece that reads as a spotter and cannot spot.

## The trap this fold walks into

**A scene carrying a node whose script you just deleted cannot be LOADED, and the importer
skips a piece whose scene it cannot open — silently.** So the order is: retire the code, strip
the dead nodes from the scenes, and only then re-run the importer to add the replacements.
Doing it the other way produces an import that reports success and changes nothing.

**And read the import's `log`, not its `errors`.** `ImportPipeline.run` puts validation
failures in `log`; a run that aborted on four bad doc keys still returns an empty `errors`
array. Two clean-looking runs were wasted on that.
