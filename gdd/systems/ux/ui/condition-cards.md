---
title: Condition cards
type: system-note
---

# Condition cards

*Design note for [Dissent Horizon](../../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

**Anything true of the selected piece that is not one of its numbers** — an effect acting on
it, a benefit it carries — is drawn as a card in the info panel, and every such card is a
[`ConditionCard`](../../../../scripts/interface/hud/condition_card.gd).

## Which row a mechanic goes in

**UBIQUITY DECIDES, not construct.** A mechanic various units across the game use is a WIDGET
in [`InfoWidgetRow`](../../../../scripts/interface/hud/info_widget_row.gd) — a fixed row the
player learns once, where a card's absence means "this piece has none". Something particular
to a faction or a piece is a CARD in
[`ConditionRow`](../../../../scripts/interface/hud/condition_row.gd), where the set changes with
what is selected.

| Row | Holds | Because |
|---|---|---|
| widgets (top) | name, hit points, weapon, movement, sight · detect, garrison | every faction fields pieces with these; the row's ORDER is the thing being learned |
| conditions (bottom) | status effects, hold fire, energy and dominion production | faction- and piece-specific, or a STATE the piece is in right now; the set is the information |

Two consequences worth naming, because they are where the rule earns its keep:

- **Detection shares the sight widget rather than getting a card.** Sight and stealth
  detection are one question — *how far can this piece see, and what can it see* — so one
  card carries both figures and one hover paints both rings. A piece with no detection sweep
  says so by reporting one figure under the plain caption; a piece with one reads
  `sight · detect`. Two representations of one widget, not two widgets.
- **Hold fire is a card, though every armed piece can hold.** Ubiquity decides where a
  CAPABILITY goes; hold fire is a state the piece is in, like a status effect, so it is drawn
  where states are — persistent and neutral, with the badge `StatusVisuals` floats over the
  unit. Its owner's to see only.
- **Garrisons are a widget, not a card**, even though only some pieces have one. Transports,
  bunkers, the Compound and the stock truck's cage are all the same component, used across
  every faction — which is the test. The caption reads `bunker` when the host fires what it
  holds, and hovering a bunker paints the fire envelope its occupants shoot through.

## Two constructs, one card

**They are separate under the hood, and the card does not pretend otherwise.**

| | `StatusEffect` | passive ability |
|---|---|---|
| what it IS | a NODE, child of the affected entity | an id in `AbilityCatalog`, `passive: true` |
| authored as | a scene under `scenes/entities/status_effects/` | a `kind: AbilityDefinition` doc |
| lifetime | `duration_ticks`, ticks itself down, removes itself | permanent while the piece lives |
| stacking | `max_stacks`, `reapply_mode` | none — you have it or you do not |
| where the EFFECT is implemented | the effect's own script (`_on_apply`/`_on_tick`) | ad hoc, wherever the mechanic lives |
| how it arrives | applied by a projectile, an `EffectApplicator`, a trigger | granted by the piece, or unlocked with dominion |
| drawn in the WORLD | yes — `StatusVisuals` tints the host and floats an icon | no |

**What they share is the QUESTION a player asks of either** — *what is this, is it helping
me, and will it last?* — so the CARD is shared and the models are not. That split is
deliberate and is the current answer rather than a permanent one; see the TODO below.

## Three channels, and each is readable alone

A player must be able to tell an affliction from a benefit without reading anything, so none
of these depends on the others:

| Channel | Drawn as | Says |
|---|---|---|
| **valence** | a coloured edge: green at the **top** for a boon, red at the **bottom** for an affliction, nothing for neutral | good or bad for this piece |
| **duration** | a depletion sweep across the card's base, draining as it runs out | temporary, and how much is left |
| **availability** | the whole card greys | real, offered, not yours yet |
| **rate** | a small figure in the card's corner | what this piece banks per cycle |

**The rate is per PIECE, and that is the point of having it here at all.** The economy panel
already gives a commander-wide income; what it can never say is WHICH building is earning it.
A Compound's figure moves as it fills, because it pays per prisoner.

**A Warlord's figure is what it would bank ON ITS OWN.** The sweep pays less when two
Warlords share a follower (`AnarchicalDominion.followers` de-duplicates), and subtracting it
on the card would make the number unreadable — the player cannot see the other Warlord's
reach from this panel, so the card would appear to be wrong. `followers_of` is the
un-de-duplicated count, and it exists for exactly this.

**Position as well as colour on the valence edge**, so the pair survives a colour-blind
reader and a grey screenshot — red and green alone would not.

**A persistent condition draws NO sweep at all.** Absence is the signal and it is a stronger
one than a full bar, which reads as *just started* rather than as *does not run out*. This is
the channel that separates "on fire" from "carries an aura" at a glance, and it is why the
duration channel is worth having even though every shipped effect is temporary and every
passive is permanent: the day one of them is the other, the card is already right.

**A bane's sweep sits clear of its edge.** Both live in the card's base strip; drawn last,
the sweep covered the red entirely and an affliction only read as one once it was nearly
over.

**NEUTRAL is a real answer, not a missing one** (`Valence.Kind`). A condition can genuinely
be neither, and forcing such a thing to claim it is good or bad puts a coloured edge on a
card that means neither. It is also the safe default for a condition whose author has not
decided.

## Where each side authors its valence

- A **status effect**: `valence` on its SCENE, beside `host_tint` and `indicator_icon` — the
  same script is two effects, and a `SlowStatusEffect` is a bane thrown at an enemy and would
  be a boon on a friendly brake. Only the scene knows which one it is.
- A **passive ability**: `valence:` on its doc, validated by the importer against
  `SpecRegistry.VALENCE_VALUES`.

## Hovering a card paints its reach

Both rows raise the same `ranges_hovered(entity, kinds)` the info widgets do, so the
controller has one thing to listen for. What a card reveals:

- a **status effect** with `effect_radius > 0` paints a circle at its host
  (`EntityRanges.Kind.EFFECT`);
- a **passive ability** paints the collider its doc names in `reveals:` — an
  `EntityRanges.Kind`, so the ring is the shape the SIMULATION sweeps rather than a circle
  re-derived from a number. See [range-reveal](range-reveal.md).

## A multi-selection shows unit cards and nothing else

**Every row in the panel is single-selection only** — widgets, conditions and passives alike.
A group has no single answer to any of the questions a row asks, and a merged description
would describe a unit that is not on the field. What a multi-selection shows is WHO is
selected: the summary `CommandableCard`s, and the detail cards for what the selected
producers are training.

The passive row was the last to follow the rule. It used to draw for a group deliberately —
"what standing benefits are in this selection" — and that was defensible while its cards
looked like nothing else. Once every card in the panel became a `ConditionCard`, a passive
drawn for a group read as a status effect on all of them, which is a stronger wrong reading
than the right one was worth. `PassiveAbilityRow.passives_in` still answers for a group,
because it is a pure query worth being able to ask; the ROW does not draw one.

The same rule is why a hover paints only one piece's reach: a reach belongs to one piece
standing in one place, and painting one arbitrary member's aura for a card that speaks for
twelve would lie about which one.

> **TODO — should the two constructs merge?** Alex raised it and it is genuinely open. The
> case FOR: they already share a card, a valence, a reach and a tooltip pair, and "a passive
> is a status effect with no duration that the piece applies to itself" is close to true.
> The case AGAINST, and what a merge has to answer first:
>
> 1. **A passive has no runtime object at all.** It is a table lookup, and its effect is
>    implemented wherever the mechanic lives (`Commander.kill_bounty_rate`,
>    `Garrison._emit_positional_bonus`). Merging means every passive becomes a node on every piece
>    that carries one, which is a real per-entity cost for a fact that never changes.
> 2. **Acquisition differs completely.** An effect is APPLIED by something; a passive is
>    GRANTED by the piece or bought with dominion. `is_enabled` has no counterpart on the
>    effect side and would have to grow one.
> 3. **The authoring homes differ for good reasons.** An effect is a scene because its
>    tuning is a scene (tint, icon, blink, frame mask); an ability is a doc because it is
>    referenced by id from pools, sanction grids and HUD cells.
>
> A cheaper middle step, if the card is the part that mattered: keep both models and let a
> passive OPTIONALLY name a `StatusEffect` scene it applies to its own host, which is how a
> passive would gain per-tick behaviour without every passive becoming a node.
