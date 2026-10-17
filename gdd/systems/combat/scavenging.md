---
title: Scavenging — wrecks, and infantry that strip them for a better weapon
type: system-note
---

# Scavenging

*Design note for [Dissent Horizon](../../../CLAUDE.md). Decided and built 2026-10-17
(`Wreck`, `Interaction.Type.SCAVENGE`, `Weapon.scavenged`, the `wreck:` and weapon
`scavenged:` doc keys, and the `nt_wreck` token). The Anarchists are the faction it was built
for; nothing in the mechanism names a faction.*

A destroyed grounded vehicle leaves a **wreck** where it fell. An infantry unit that carries a
**scavenged weapon** can strip the wreck for parts, and switches to that weapon for good.

## Wrecks

**Every grounded vehicle leaves a wreck when it is destroyed** — a mobile MECH unit that is
not an aircraft (`Wreck.leaves_wreck`), whoever owned it. Infantry, structures, aircraft,
emissions and planted charges leave nothing; a hovering helicopter is an aircraft (it has an
`Aerial`), so it leaves nothing either. A vehicle that dies *inside* a transport leaves nothing, since it is not in the world
to leave one.

- **Where:** at the vehicle's position on the tick it died. It is placed from the death
  chokepoint (`Actor._on_death` → `Wreck.leave_for`), while the map and position are still
  valid.
- **Whose:** the neutral commander's (id 0), so it draws no aggro and belongs to no side.
- **How long:** it stands for the token doc's `wreck: {lifespan: …}` — **30 s**
  ([nt_wreck](../../factions/neutral/tokens/nt_wreck.md)) — then expires through a `Lifespan`.
  An expiry is not a death: nothing is destroyed, so there is no bounty and no death reaction.
- **What it is:** a token — no cells, no hit points, uncommandable. It cannot be shot, does
  not block movement, and is hidden under fog like any other piece.

## Scavenging a wreck

**Scavenge is an [Interaction](../../../scripts/entities/components/interaction.gd)
(`SCAVENGE`), so it is ordered the way a hijack is: right-click the wreck.** The unit walks to
it and works on it for **3 s** (the interaction's `duration`, authored on each unit's
`Interactor`); on completion the wreck is consumed and the unit's Loadout switches to its
scavenged weapons.

| Rule | Decided |
|---|---|
| **Any wreck** can be scavenged — an enemy's, a neutral's, or the scavenger's own side's. A lost vehicle still pays its infantry back. | 2026-10-17 |
| **One wreck upgrades one unit.** Completing the scavenge consumes it (it leaves play at once), so a second unit working on the same wreck finds nothing and its order ends. Wrecks are a contested prize. | 2026-10-17 |
| **Taking damage pauses it**, the way it pauses a hijack (`Interaction._STAGGER_BLOCKED_TYPES`): scavenging in the middle of a fight waits until the unit stops being hit. | 2026-10-17 |
| **Always available.** Every armed Anarchist infantry unit can scavenge from the start; nothing unlocks it. The Scavenge *sanction* (the kill bounty) is a separate thing and is unchanged. | 2026-10-17 |
| **Once per unit, for good.** A unit that has scavenged is refused the interaction, so it never consumes a wreck for nothing. The upgrade lasts until the unit dies. | 2026-10-17 |

## The scavenged weapon

**A scavenged weapon is a whole weapon of its own, not a modifier on the ordinary one** —
a second entry in the unit's `weapons:` list marked `scavenged: true`. Until the unit
scavenges, it is carried but not live; afterwards it is the only kind that is, and the
ordinary weapons beside it stop being live (`Loadout.get_weapons`). Keeping it a separate
weapon is what lets the two forms differ in anything later — damage type, reach, a status
effect — rather than only in what a multiplier can express.

**Live is the one gate.** Everything that asks what a piece shoots with — targeting, aggro and
reach, the HUD's weapon card and charge dials, the bot's estimates — goes through
`Loadout.get_weapons`, so a weapon waiting on a scavenge is invisible to all of them. Aggro is
re-derived the moment the switch happens. `Loadout.all_weapons` is for the few readers that
must count every weapon whatever is in use (the simulation digest).

**Today's scavenged weapons reload twice as fast** (half the `reload_time`), and are otherwise
copies of the ordinary ones; for a single-shot weapon the split is halved with it, since for
one round the split and the reload are one number
([weapon-cadence](weapon-cadence.md) §The cycle). The values live in each unit's doc:

| Unit | Doc |
|---|---|
| Irregular | [an_bioLight_builder](../../factions/anarchical/units/an_bioLight_builder.md) |
| Shock Trooper | [an_bioMedium_antiMech](../../factions/anarchical/units/an_bioMedium_antiMech.md) |
| Warlord | [an_bioMedium_dominionGen](../../factions/anarchical/units/an_bioMedium_dominionGen.md) |
| Juggernaut | [an_bioStrong_antiLight](../../factions/anarchical/units/an_bioStrong_antiLight.md) |

These are the Anarchists' armed infantry as of 2026-10-17. The Sharpshooter has no weapon yet
and the Sapper and Hijacker are unarmed, so none of them can scavenge.
TODO: a weapon authored for the Sharpshooter later needs its scavenged twin (and an
`Interactor` with the SCAVENGE interaction) to take part.

## Authoring

- **The wreck** is `gdd/factions/neutral/tokens/nt_wreck.md`; `wreck: {lifespan: <s>}` gives a
  token the `Wreck` component. Its model is generated
  (`tools/structure_models` → `assets/meshes/entities/tokens/nt_wreck.res`).
- **A scavenged weapon** is a `weapons:` entry with `scavenged: true`. It may name the ordinary
  weapon's emission by id (`emits: irregular_bullet`) rather than repeat it inline.
- **Its position is scene-authored, like every weapon's**, and the importer creates the new node
  without one. Give it its twin's transform by hand, or its shots leave from the carrier's feet
  (the launch-from-origin warning says so): the Warlord's scavenged rockets hit the ground until
  this was fixed on 2026-10-17.
- **The interaction is scene-authored**, like every Interaction: an `Interactor` node on the
  unit's scene holding a `SCAVENGE` Interaction with `duration = 3.0`. It carries no
  `interact_shape`: a wreck is not on a targetable layer, so a shape query cannot find it, and
  the default contact reach (the unit touches the wreck) is used instead.

## Not done

- TODO: **the CPU bot does not scavenge.** It will not order an Interact on a wreck; its
  infantry only switch weapons if a player orders it (debug mode).
- TODO: **nothing shows that a unit has scavenged** beyond its weapon card. A badge or tint
  ([condition-visuals](../ux/ui/condition-visuals.md)) is undecided.
- TODO: **no alert** is raised when a wreck appears or is scavenged.
