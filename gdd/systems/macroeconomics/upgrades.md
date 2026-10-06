---
title: Upgrades — one-time research at a structure
type: system-note
---

# Upgrades

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md
carries only the pointer.*

**An upgrade is a one-time, commander-wide purchase, researched at a structure.** It is authored
as a `kind: Upgrade` doc ([spec importer](../../../tools/spec_import/README.md) §kind: Upgrade),
researched wherever a structure's doc lists it under `researches:`, and it changes what its
`modifies:` entries say. The first one was [[advanced_targetting|Advanced Targetting]]. Decided
with Alex, 2026-09-30.

## The rules

- **Research is a job in the global production queue.** A research purchase is an ordinary TRAIN
  purchase: priced from `technology.json`, charged on submit, waiting out a shortfall, cancelled
  with a refund, run on the structure's `Production` component, and slowed while the commander
  is infrastructure-strained. It shares everything with training except the ending: when the job
  finishes, `Production._complete_research` calls `Commander.complete_upgrade` and nothing
  spawns. `researches:` merges into the same `producible_types` list as `trains:`.
- **Researching does not make a structure a unit producer.** Code asking "does this train
  units" asks `Production.trains_units()`, not whether a `Production` component exists: the
  rally point, the idle-producer hotkey, the bot's throughput buildings and placement scoring,
  and a placement's need for a walkable side. A research-only structure has none of those.
  Queue dispatch still reaches it, since that is where research runs.
- **One purchase per upgrade.** An upgrade that is owned, queued or running cannot be ordered
  again: `Commander.is_research_taken` makes its unmet need `ALREADY_RESEARCHED`, which refuses
  the order and draws the button LOCKED. A standing research is demoted to a one-off, because
  there is nothing to repeat.
- **Commander-wide and immediate.** Owning an upgrade changes every affected piece the
  commander fields, now and later, captured pieces included; a piece captured AWAY loses its
  old owner's upgrades and takes its new owner's. Readers ask `UpgradeCatalog` for the value
  in force when they need it, so a piece trained before the research and one trained after
  cannot disagree. The one exception is the hit-point maximum, which is read in too many
  places to look up each time: the piece re-applies it whenever its commander changes or
  researches something.
- **It survives the building.** Losing the structure that researched an upgrade does not take it
  back. That matches the rule for tech gates: losing a gate blocks new purchases, and what is
  already fielded stays ([pacing/tree-shape](pacing/tree-shape.md) §Pitfalls).
- **The effect is authored, not coded.** Each `modifies:` entry names which pieces (below), and
  carries exactly one effect.

## What an upgrade can change

A modifier selects by **`piece:`** (one piece id) or by **`frame:`** (every UNIT of that frame,
BIO or MECH; structures are never selected by frame, since "every BIO unit" is what a player
would mean). An effect about an ability also names the **`ability:`**.

| Effect | Means | Two upgrades on one value |
|---|---|---|
| `range` | the ability's reach becomes this shape's radius (piece + ability) | the **longest** wins, so research order cannot shorten it |
| `hp_factor` | the hit-point maximum is multiplied by this | the factors **multiply** |
| `rearm_rate_factor` | a docked aircraft refills its charged weapon this many times as fast (piece only, and it must carry a `charged:` weapon) | the factors multiply, and with the bay's own charge rate |
| `cooldown_rate_factor` | the pool holding this ability recharges this many times as fast (piece + ability) | the factors multiply |

Every factor is a RATE, so 2.0 halves a rearm and 1.5 takes a 30-second cooldown to 20. A
rate is what the code multiplies; a duration cut of a third is the same 1.5.

**A changed hit-point maximum keeps the unit's fraction of health.** A unit at 60 of 100 that
gains a quarter more goes to 75 of 125, so a damaged unit benefits in proportion. Capture by a
commander without the upgrade brings it back down the same way (Alex, 2026-10-06; "captured
pieces swap upgrades" is accepted for now).

## Where upgrades are researched

The question was which building an upgrade belongs in: production buildings, tech buildings, or
either. **Leaning, and what Advanced Targetting does: tech buildings by default**, and a
production building only for an upgrade that should deliberately cost production time.

| Researched at | What it costs the player | What it does to the structure |
|---|---|---|
| **A tech structure** | Energy only. Tech structures run no other jobs, so research takes nothing else from the player. | Gives the structure a job, and gives a second copy a real use: two upgrades researched at once (the tempo purchase in [building-roles](pacing/building-roles.md) §Upgrades). The research sits behind the tech gate, so it arrives with the tier it belongs to. |
| **A production structure** | Energy **and production time**. A structure runs one job at a time, so a research blocks unit output for its duration: "army or upgrade" becomes a real trade (the StarCraft and Age of Empires shape). | Makes the second producer more valuable again, since it keeps units flowing during research. The upgrade can be bought as early as the producer. |
| **Either, per upgrade** | Chosen per upgrade: whether it should compete with production. | Most flexible; the cost is that players must learn where each one lives. |

Why tech structures by default:

- **G16 (no mutually exclusive macro dilemmas).** Research at a producer is exactly an "army or
  economy"-shaped trade, made per job. At a tech structure the only trade is energy, which every
  purchase already makes.
- **The payoff sits with its gate.** Advanced Targetting only matters once Bombards exist, and the
  Operations Center is what unlocks the Bombard. Researching it there means the upgrade and the
  thing it improves arrive together.
- **It gives tech structures a second role** without a weapon or a charge. That is the rider
  building-roles asks for, and it passes that note's rider rule: nothing dedicated does the job
  better per cost.

A production-structure upgrade is still the right tool when an upgrade's price should be felt as
lost output, for example a strong unit-specific upgrade that should not come free while its
producer keeps training.

## Advanced Targetting's numbers

**800 energy, 45 seconds, at the Operations Center** (a starting guess, 2026-09-30). The price
sits a little under a Bombard, because the upgrade only pays off once Bombards exist and is worth
more with each one. What it buys is survivability: a spotter at `ground_range_siege` can stay
outside most structures' vision while it calls a strike in, where without it the Recruit has to
walk into the defence it is marking. The leash on a beacon riding a unit stretches to match.

## Not done

- **TODO: the CPU commander never researches.** The bot's production code picks only combat and
  utility units from a producer's list, and an upgrade is neither, so it is skipped rather than
  mistaken for a unit. The bot needs its own reason to buy one ([ai](../ai/)).
- **TODO: nothing shows which upgrades a commander owns** apart from the research button going
  dark ("Already researched").
- A new effect goes into `SpecRegistry.MODIFIER_EFFECTS` together with the reader that honours
  it.

Tests: `tests/test_Upgrades.gd`, `tests/test_UpgradeFactors.gd`.
