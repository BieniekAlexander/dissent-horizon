---
title: The Colonial dominion loop
type: system-note
---

# The Colonial dominion loop

*Design note for [Dissent Horizon](../../../CLAUDE.md).*

Steps 1-4 of the work order below shipped 2026-09-17; step 5, the calibration, on 2026-10-05:
a 30 s sentence served one captive at a time, 150 dominion a captive, and a 200-energy Servant
(Alex; measured in [pacing/dominion-rate-analysis](../macroeconomics/pacing/dominion-rate-analysis.md)
§Colonial decision). Nothing here is provisional.

The economics behind it — why throughput rather than a stock, and which knob does what — are in
[design-framework/proposals](../../design-framework/proposals.md) §Colonial dominion. This note
owns the MECHANICS; that one owns the model and its open calibration.

---

## Why it changes

Dominion paid for as long as a captive is *held* makes a delivery a one-time fill: once a
Compound is full it pays forever, the route stops mattering, and Compound placement stops being
a decision. Paying for a captive's *term* makes the rate depend on arrivals, so where the
Compound stands relative to a Shelter is a live trade against where it stands relative to the
buildings it supports.

## A captive serves a sentence

**A deposit no longer converts a captive into a Servant.** The captive is held as itself for
`sentence_length`, and pays dominion each cycle while it serves. The Compound's income therefore
follows the arrival rate rather than climbing to capacity and staying there.

**A Compound sentences ONE captive at a time (Alex, 2026-10-05).** The captive serving pays
`dominion_per_unit` (25 per 5 s cycle, 5/s) for its 30 s term, 150 in all; the others wait their
turn in arrival order, paying nothing, their terms not yet started. The places beyond the first
are a QUEUE, not extra earners: they let a truck unload a full cage at once and keep the Compound
busy between deliveries. `Garrison.SENTENCES_AT_ONCE` / `Garrison.paying_count()`.

Why one at a time rather than all at once: with every captive serving at once, a Compound's
income is its occupancy times the rate, so its capacity is a second rate knob tangled with the
sentence. Serving one at a time caps a Compound at one captive's rate (5/s), so its number is
"how many Compounds do I feed" and the sentence is purely the value of a captive (`R × T`). It
also makes deposit time count: a truck still handing over its cage holds the Compound's queue.
The pitfall accepted: a Compound fed faster than one captive per 30 s backs up and refuses
deposits, so working two Shelters into one Compound wastes trucks — the player builds a second
Compound instead, which is the decision this is meant to create.

`sentence_length` is a constant. With one-at-a-time serving it sets the value of one captive and
how many captives per minute a Compound can turn over (two).

**A finished sentence CONSUMES the captive.** The unit is removed from the game; the Compound
produces nothing but the dominion it paid along the way and the cooldown reduction it emits on
the way out. This supersedes conversion-on-deposit, and with it the idea that internment produces
labour at all: the Colonial route now spends bodies rather than re-badging them, which is what
separates it from the Anarchical one, where a Warlord converts a Terrestrial and keeps the unit
in the world. It is also the faction's lore in one mechanic — a power that consumes what it
takes faster than it replenishes.

The pitfall accepted: a Shelter's population is finite per unit time, so a Colonial player who
works one hard is burning a resource an Anarchist opponent would have turned into soldiers. That
is the trade, not a leak.

**The Compound becomes a CLOSED garrison.** Nothing may be ordered into it — the Servants-only
allowlist goes, and deposit is the only way in. It is no longer somewhere to park a spare body;
a Servant reaches it only by riding a Stock Truck (§Servants as dominion). `CLAUDE.md` §Terminology uses the Compound as its example of
a garrison that is *not* closed; that entry changes when this lands.

Release on destruction is unchanged, and worth stating because it now means something different:
a destroyed Compound hands every occupant back to the commander it was taken from, so killing one
mid-term rescues the prisoners rather than merely denying the income.

## Servants as dominion

**A Servant may ride a Stock Truck, and a delivery takes it to the Compound with the captives.**
The truck's cage admits Servants by order and no other piece (a `pieces:` allowlist on masks
opened for light biological infantry), sharing its three places with prisoners; capture by
crush is unchanged. A deposit hands over everything in the cage, and a Servant serves a
sentence like a prisoner — paying dominion each cycle, consumed at the end.

**The difference is who may let it out.** An order — Evacuate, or an occupant's card — releases
only the host's own side, so a Servant can be walked out of a truck or out of a Compound before
its sentence ends, and the captives beside it stay. See
[garrison-and-transport](garrison-and-transport.md) §The two directions of the door are separate
statements.

What it is for: Servants become transportable, and they are a cost-inefficient way to buy
dominion — 200 energy for one 150-dominion sentence, about 1.3 energy per dominion, against the
free bodies a Shelter supplies. An option for a player with energy and no prisoners, not a route.
The price was held to 150–300 (Alex, 2026-10-05).

TODO: a truck tasked on a Shelter (`TaskShelter`) deposits whatever it carries, so a Servant
riding a tasked truck is sentenced on the next delivery without the player asking. Whether
tasking should leave Servants aboard, or refuse to run with them, is open.

TODO: the bot neither loads Servants into trucks nor sentences them.

## The positional bonus is an event, not a rate

**On a sentence completing, the Compound reduces the cooldown of every ability pool on every
edge-adjacent friendly structure by a percentage.** Work Detail's passive per-occupant recharge
rate is deprecated and replaced by this.

The reason for the swap is that the two halves of the building should tell one story. A passive
rate rewards *holding* bodies, which is exactly what the sentence model stops rewarding; a
per-completion reduction rewards *turning them over*, which is what the dominion rate now
measures too. A Compound worked hard by a short route is worth more at both jobs at once.

Unchanged: adjacency is edge contact between footprints, the supporter must be finished and
owned by the same commander, and a commander who cannot cover its upkeep lends nothing.

**The percentage is of the pool's FULL cooldown**, not of its remaining time: a fixed chunk of
time per completion, which a player can count ("three sentences off the next scan") and which can
finish a cooldown outright. A share of the remaining time was rejected for the opposite property
— it tapers toward ready, so the last stretch of a long cooldown would be immune to the mechanic.

Nothing is banked: a completion while an adjacent pool is already charged is worth nothing there.

## The pieces this changes

Target values for the change; once applied, the spec docs own them.

| Piece | Change | Consequence |
|---|---|---|
| Stock Truck | armour `MEDIUM`; speed back to `QUICK` (see below) | survives the roads it now spends its life on (the damage table's anti-light types all fall a step against MEDIUM) |
| Shelter | spawn interval `10`, capacity unchanged | arrivals become frequent and small, which is what makes route length bind at map distances rather than only at absurd ones; the population cap still buffers a Shelter left alone, for a third as long |

**The truck is fast again, and gated instead (Alex, 2026-10-01).** It was slowed to `1.75` to
stop it being oppressive at the start of a match, which also put the Colonial "slow to traverse
the map" identity on the dominion route ([design-framework/matchups](../../design-framework/matchups.md)).
That job now falls to its prerequisite: the truck requires the Compound (`cl_infrastructure`),
so it is not available immediately, and its speed is back at `QUICK`. It scouts and chases again.
TODO: its price may rise too.

## What it depends on

Tasking a truck on a Shelter is its own system, and the first consumer of it:
[commands/unit-tasking](../commands/unit-tasking.md).

## Work order

1. ✅ **Sentences.** `sentence_length` on the garrison, a per-occupant term, and consumption at
   the end of it. Retired `garrison.interns` as the deposit marker, and closed the Compound's
   garrison (the Servants-only allowlist gone). `CLAUDE.md` §Terminology's closed-garrison
   example changed in the same change, and the deferred item for the bot parking a spare Servant
   for dominion — retired, because there is nowhere to park one now. `Garrison.deposit_from` /
   `Garrison._physics_process` / `scripts/entities/components/garrison.gd`.
2. ✅ **The positional bonus.** Emitted on completion (`Garrison._emit_positional_bonus` →
   `Abilities.reduce_all_cooldowns`); the passive recharge-rate constant is retired and
   `work_detail`'s ability doc rewritten around the event.
3. ✅ **Piece values.** Stock Truck (`armour: MEDIUM`; its speed has since returned to `QUICK`) via the spec doc and an
   importer run; Shelter's `spawn_interval` (10s) hand-authored on `nt_shelter.tscn` directly —
   Shelter is not yet part of the spec-doc schema (`tools/spec_import/README.md` §Doc schema).
4. ✅ **Tasking.** [commands/unit-tasking](../commands/unit-tasking.md) — `TaskShelter`. The bot
   does not issue it yet (`tests/test_BotCommandCoverage.gd`).
5. ✅ **Calibration** (2026-10-05). One-at-a-time sentencing, `sentence_length: 30` on the
   Compound, `dominion_per_unit` 25, the Servant at 200 energy — chosen from the sweep in
   [pacing/dominion-rate-analysis](../macroeconomics/pacing/dominion-rate-analysis.md).

Steps 1-3 stood alone: the loop worked with hand-driven trucks before tasking existed.

## The dominion-rate projection

**Built alongside tasking, not originally scoped here:** the HUD's forward-looking dominion
projection (`DominionBar`'s translucent bar region) used to assume "if the current rate held"
— valid under the old indefinite-hold model, wrong under sentences, where occupancy decays as
terms complete. `Commander.projected_dominion_rate()` derives a steady-state rate instead, from
which Shelters have tasked trucks right now: round-trip time at the trucks' own speed against
each Shelter's regeneration, capped by how many captives the receiving Compound sentences at once
(one) — the model's `min(Φ·τ, K)` with K the captives serving rather than the places held, with `c`/`t_l`/`t_u`/`μ`/`m` dropped as negligible for the one-truck
openings this is aimed at. See
[ui/economy-bars](../ux/ui/economy-bars.md) §Rate projection and `tests/test_ProjectedDominionRate.gd`.
