---
title: Building roles — the marginal value of the next copy
type: system-note
---

# Building roles

**TODO — research, nothing decided.** Part of [pacing](README.md).

**The "what next?" decision is a comparison of marginal values**, and each thing a structure
confers has its own curve for the Nth copy:

| What it confers | 1st copy | 2nd and later | Here |
|---|---|---|---|
| **Unlock** (tech gate) | everything | ~0: insurance against a snipe, nothing more | tech 1 and 2 |
| **Production** | full | full: throughput and a second rally position | barracks, factories |
| **Weapon** | full | full, but local: covers a different spot | statics, the Bombard |
| **Ability charges** | full | full, unless uses outrun opportunities to use them (see below) | Citadel, Storm Cell, Hideout |
| **Purchased upgrade** | the upgrade | tempo only: two upgrades researched at once | TODO: none built yet |
| **Infrastructure / economy** | full | full, until the cap it feeds | the infrastructure structure, extractors |
| **Staying in the game** (win condition, if adopted) | everything | insurance, worth more as the opponent's finishing tools arrive | command centre |

A **pure unlock** has a step-function value, so there is never a decision about copy two:
build one, and never another unless it dies. That decision is simple (G1), but it is also
already solved. **Adding a second role gives copy two a real value** and so creates a decision.
This is G6, and it matches the brief's example: with one production and one tech structure
available, a pure tech structure leaves only one sensible next purchase, while a tech
structure with a weapon or a charge makes both candidates.

**A charge's marginal value falls when charges outrun targets.** An ordnance is worth its
effect only when a good target exists. Past the rate at which a player finds good targets,
more charges add little. A shared pool (one charge granting several abilities) keeps the
*rate* fixed while widening the *options*; see
[dominion-and-ordnance](dominion-and-ordnance.md).

## The rider rule

**A secondary role must be worse per cost than the dedicated piece that does the same job.**
If a tech structure's weapon beats a static defence per energy, or its charge beats a support
structure's, the tech structure becomes the spam building and the dedicated piece dies.

State it as a check: *for each role a structure carries, the structure's cost must exceed the
cost of the cheapest dedicated piece that provides that role at the same strength.* The unlock
alone is then the reason to build the first copy, and the rider is what makes the second one
a question rather than an answer.

The rider may still *win on position or durability*. A tech structure's weapon stands where
the tech is, and a STRONG command centre is a durable caster. Those are the interesting
reasons to pick it, and they are what makes the choice positional (G4) rather than
arithmetical.

## Upgrades: the tempo purchase

A structure offering two researched upgrades makes copy two a pure tempo buy: both upgrades at
once, for the full price of a structure. That is a legitimate decision, and G16's "shy away
from mutually exclusive outcomes" is satisfied because nothing is lost by waiting. The
pitfall is purely one of **price**: if the structure is cheap relative to the upgrades, copy
two is always bought, and the queue becomes a solved checklist. Price structures that offer
upgrades well above the upgrades themselves.

TODO: no purchased upgrades exist yet, so this section is ahead of the game.

## Pitfalls

1. **Rider dominance.** A secondary role better per cost than the dedicated piece (§The rider
   rule).
2. **Legibility.** A multi-purpose structure is a richer target, but only if the attacker can
   see what each copy does: which one holds charges, which one is the only gate. Visible
   states (charge pips, the gate's silhouette) are what make target choice a decision rather
   than a guess ([condition-visuals](../../ux/ui/condition-visuals.md)).
3. **Correlated loss.** When one structure carries a gate, a weapon and a charge, one snipe
   removes all three. That is more volatile, which is fine late (G3) and bad early (G17).
   Early-tier structures should carry fewer roles than late ones.
4. **Insurance is dead weight until it is not.** Duplicate gates cost army. The value of that
   insurance grows with the opponent's ability to snipe (late, and against fast or ranged
   threats), which is the right shape: the question arises only when it should.
