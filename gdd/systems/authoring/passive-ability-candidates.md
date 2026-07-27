---
title: Passive ability candidates
type: system-note
---

# Passive ability candidates

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

**REVIEWED 2026-09-04.** Every row below is a mechanic that behaves like a passive ability
and was implemented as something else. Alex approved the list with placement caveats, and
those caveats turned out to be a RULE rather than a set of exceptions — see
[ui/condition-cards](../ux/ui/condition-cards.md) §Which row:

> **Ubiquity decides the row.** A mechanic various units across the game use is a WIDGET in
> the unit summary; something faction- or piece-specific is a CARD in the conditions row.

That reclassified four of the entries below out of the passive-ability system entirely, which
is the useful outcome: they did not need to become abilities, they needed a place to be
DRAWN.

## What makes something a candidate

A mechanic belongs in the passive-ability system when all three hold:

1. **It is always on.** No charge, no order, no aim point — it is true because the piece
   exists. (An `Abilities` pool with `passive: true` says exactly that.)
2. **A player would want to see it on the piece's card**, because it is not derivable from
   the numbers already on screen.
3. **Converting buys something.** Usually one of: a HUD card the mechanic did not have, a
   reach the player can now see, or — the big one — *a second piece can have it without
   code*.

The third is the one that decides. `AnarchicalDominion` named `an_bioMedium_dominionGen`
outright, so "is this a dominion aura" was a fact about ONE unit; asking what a piece GRANTS
means a second such unit needs a doc. Anything already generic gains only the card.

**A capability is not a passive.** `Repairs`, `Builds` and `Production` say what a piece may
be ORDERED to do; a passive is something that happens without being ordered. Presence-is-the-
check components are deliberately not on this list.

## Converted already

| Mechanic | Ability | What converting bought |
|---|---|---|
| Compound speeds adjacent structures' cooldowns | `work_detail` | the card, the mechanic's first statement in a doc |
| Warlord banks dominion from nearby infantry | `retinue` | the card, the reach reveal, and sources found by ABILITY rather than by piece id |
| Kill bounty on destroyed enemies | `scavenge` | (was always one — the model the rest follow) |

## Resolved by placement rather than by conversion

These were on the list as passive-ability candidates and are now widgets or cards. None of
them became an ability, because none of them needed the ABILITY half — a doc, an id, a pool —
only the drawn half.

| Mechanic | Now | Why not an ability |
|---|---|---|
| **Stealth detection** | the sight widget's second figure (`sight · detect`), sharing one hover that paints both rings | one question, not two: *how far can this piece see, and what can it see* |
| **Garrison / bunker fire** | the `hold` / `bunker` widget, hovering to paint the fire envelope | every faction fields garrisons; the component IS the mechanic |
| **Charged ammunition** | the weapon widget greys (`TINT_LOCKED`) while a reloading weapon is dry | a state of an existing widget, not a thing the piece HAS |
| **Crush** | named in the movement widget's hover | a rule about two pieces meeting, looked up rather than glanced at |
| **Energy / dominion generation** | cards in the conditions row, badged with what THIS piece banks per cycle | the economy panel gives a commander-wide rate and can never say which building earns it |

**The Warlord is the edge case, and it is drawn deliberately.** Its dominion IS the `retinue`
passive, so its figure rides on that passive's own card rather than becoming a second one.
The number is what it would bank ON ITS OWN — the sweep pays less when two Warlords share a
follower, and subtracting that here would make the card look wrong for a rule the player
cannot see from this panel.

## Still candidates — a reach the player cannot currently see

These have a real collider and a persistent effect, which is exactly what the card plus
`reveals:` was built for.

| Mechanic | Lives in | Carried by | Valence | What converting would buy |
|---|---|---|---|---|
| **Heal aura** — continuously heals friendly BIO units overlapping an Area3D | `HealAOE` (`scripts/entities/effects/heal_aoe.gd`) | `an_support1` | BOON | The strongest candidate on the list. It already has the shape and the tick; it has no card, no tooltip and no visible radius, so a player has to infer the whole mechanic from hit points going up. |
| **Liberation** — converts neutral Terrestrials that come close | `Liberator` / `Liberatable` | Warlord | BOON | `debug_shape_liberation_range` already exists and `EntityRanges.Kind.LIBERATION` already maps to it, so the reveal is free. Pairs naturally with `retinue` on the same piece. |

## Worth a card, with no reach to draw

Persistent and invisible, but not spatial — they would gain the card and the tooltip pair,
not a ring.

| Mechanic | Lives in | Valence | Note |
|---|---|---|---|
| **Stealth** — the piece is hidden until it acts | `Stealth` | BOON | Already drawn in the world by `StatusVisuals` (a fade). A card would name the BREAK condition, which the fade cannot. Piece-specific, so a card rather than a widget. |
| **Unpowered** — a structure's weapons and abilities are off while its commander is infrastructure-strained | `Commandable.is_unpowered` | BANE | Cheap and high-value: the state exists, has a HUD blocker already, and is currently only visible by pressing a dark button. The obvious first BANE card that is not a status effect. |
| **Veterancy rank** — accumulated experience raising a piece's stats | `Veterancy` | BOON | Drawn in the world as chevrons. A card could carry the actual bonuses, which the chevrons cannot. Note it is a SCALE, not a flag — three ranks means either three abilities or a card that reads its own level. |

## Deliberately NOT candidates

- **Crush** (`Movement.crush_class`) — a rule about a COLLISION between two pieces, not a
  property of one. Now named in the movement widget's hover, which is where Alex asked for
  it and where a looked-up rule belongs.
- **Aggro** — how a piece picks a fight. It has a reach and is already revealed by the weapon
  widget; a card would be a second name for a ring the player can already see.
- **The occupant dominion generator as an ABILITY** — the Compound banking per prisoner is
  now a conditions-row card carrying its per-cycle figure, which is what it needed. Making it
  an ability as well would add a doc and an id for a mechanic no second piece shares.
- **Movement modes and landing states** — confirmed not worth representing. They are STATES a
  piece transitions between, legible from the unit itself.

## The one that changes the shape of the list

> **TODO — a heal aura is a passive ability whose behaviour is per-tick, and nothing in the
> passive system ticks.** `retinue` is read by whoever needs it (`AnarchicalDominion`), which
> works because it is a *query*. `work_detail` moved off that shape on 2026-09-17 — it is now
> an EVENT the Compound pushes on a sentence completing (`Garrison._emit_positional_bonus`),
> closer to what a heal aura would need than a query is. A heal aura still differs: it applies
> every TICK rather than on a discrete completion, and today that is a bespoke node.
>
> This is the same seam as the merge question in
> [ui/condition-cards](../ux/ui/condition-cards.md) §TODO, seen from the other end: if a passive
> could name a `StatusEffect` scene to apply to its own host, a heal aura becomes an authored
> passive with no new machinery, and so does every other per-tick candidate here. **Settle
> that before converting anything in the first table** — converting them one at a time under
> the current model means one bespoke node each, which is what the list is trying to stop.
