---
title: The model's layers
type: system-note
---

# The model's layers

*Design note for [Dissent Horizon](../../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

## The model

One world model per commander-and-bot pair, refreshed by perception jobs that run before
every decision job, read by every manager. **A manager reads the model and the config and
nothing else.** Each layer is a pure `RefCounted` that takes the layer below as input, so each
is unit-testable from a fixture with no scene (`~/.claude/CLAUDE.md` §7).

**The model is a blackboard, and it holds STATE, never logs** (decided 2026-10-06). Two
rules, both from the compute budget being small:

- **Every signal is computed once, on its cadence, stored, and READ.** A manager that
  recomputes what the model already holds is the bug; a signal two managers want is a signal
  the model stores. This is the blackboard discipline the roadmap's utility arbitration
  already assumes, applied to perception.
- **The Markov property.** Where the past matters it is consolidated into a small number of
  present data points that overwrite themselves; where a past state stops mattering (a clip
  refilled, an ability recharged) its datum expires on its own. Nothing is appended to and
  searched later. No event log exists anywhere in the model.

**Which half lives where is decided by one test (2026-10-06): is this information part of a
human player's own perception of the game?** If the game presents it to the player, or a
player naturally holds it, it is a `Commander` fact and the bot reads the SAME signal the HUD
does. If it is a construct made for the bot — a quantisation, a heat map, a derived group —
it is the bot's alone, and it is tracked only to the extent it mirrors what a player would
hold in their head rather than to exceed it.

| information | lives on | why |
|---|---|---|
| fog of war; what is visible now (L0) | `Commander` | presented to the player; already per commander |
| remembered pieces (L1 tracks) | `Commander` | the blackboard's precedent — the snapshot meshes are the player-facing face of the same memory |
| the sight-age lattice, fields, groups (L2) | bot | a human reads the minimap; the heat map and the clusters are the bot's stand-in for that reading |
| assessment and attention (L3, L4) | bot | a commander's judgement |

The JDL levels are a sound skeleton for this bot, and the line above is the intentional part:
each new signal is placed by asking whether a player has it, not by which level it is on.

```
scene / fog ──L0 sightings──▶ L1 tracks ──▶ L2 situation ──▶ L3 assessment ──▶ managers
                                 ▲                                │
                                 └──────── L4 attention ◀─────────┘   (what to look at next)
```

### L0 — Sightings

What the fog delivers, each perception tick, for the pieces inside the bot's focus (§L4):
one `Sighting` per visible enemy or neutral piece — `{instance_id, type, owner, position,
tick, hp_fraction}` — plus, when a piece was seen to act, the ONE fact about the action that
outlives it: a weapon fired (so its clip is down), an ability used (so it is recharging).
Those become expiring state on the track (§L1); they are not kept as events.

Two gates sit on L0, both from the [ontology](../ontology.md) §Time, both with starting values
to be retuned in testing:

- **the perception floor**, 1.0 s: nothing that exists for less is delivered at all — a lead
  round never enters the model;
- **reaction latency**, per tier: a sighting is delivered only once it has persisted that
  long. `EASY` 2.0 s · `MEDIUM` 1.0 s · `HARD` 0.5 s · `IMPOSSIBLE` one perception tick
  (0.2 s at the blackboard's 5 Hz).

**Negative evidence is a check, not a set** (decided 2026-10-06, replacing the first draft's
"cells seen empty"). Per track inside the focus, per tick, two lookups — is its last-known
position fog-clear now, and was it among this tick's sightings. Clear and absent is the
evidence: a structure track goes `LOST`, a unit track takes a sharp confidence cut. O(tracks)
with a pixel read each, and no spatial bookkeeping. The `sight_age` channel (§L2) is stamped
the same way, lattice cells against the fog's cleared set on a resumable sweep — which is
what replaces `BotScout`'s raycasts ([ontology](../ontology.md) §Vision is unoccluded).

L0 is the ONLY code that touches `Commander.visible_enemies`, `visible_foreign_structures`,
`has_vision_at` and the fog. Everything above it is a function of sightings.

### L1 — Tracks: the blackboard with memory

`TrackTable` generalises `CommanderBlackboard.Entry`. Per piece:

| field | meaning |
|---|---|
| `type`, `owner`, `noun` | as today, plus the ACTIVE noun ([ontology](../ontology.md) §Pieces) |
| `last_seen`, `last_position`, `last_hp_fraction` | the last sighting |
| `velocity` | from the last two sightings; zero for fixtures |
| `status` | `CONFIRMED` (in vision now) · `BELIEVED` (out of vision, confidence above floor) · `LOST` (negative evidence, or decayed out) · `DESTROYED` (death witnessed) |
| `confidence` | ∈ (0, 1]. Exponential decay in time since last seen, with a half-life per noun — units short, structures very long, features effectively none — cut sharply by the negative-evidence check. Decided 2026-10-06; the first draft's reachable-disc rule is REJECTED, since it was the one part that needed per-cell bookkeeping and the decay plus the last-position check gets most of the honesty |
| `ammo`, `ability` | EXPIRING STATE: `{empty, refills_at}` from `Weapon.reload_time_ticks` / `clip_size` / `charged`; `{id, ready_at}` from the ability catalog's cooldown. Written when the action was seen inside the focus, read until the time passes, then gone. This is the whole of a track's "history" |
| `affordances` | the type's derived capability set ([ontology](../ontology.md) §Affordances), so higher layers reason without per-type code |

Rules, replacing today's leaks:

- **Never `is_instance_valid`.** The live reference is kept only to re-identify a piece on
  re-sighting; it is never consulted for liveness. A track leaves the table by negative
  evidence, witnessed death, or confidence falling below the floor.
- **Tracks are keyed by instance, and that is a known concession.** A player who sees a
  soldier vanish into fog and another appear five seconds later cannot say whether it is the
  same soldier; the bot can, because the table re-identifies by instance id. Decided
  2026-10-06: keep the identity, since it is what makes re-sighting cheap and no decision
  gains meaningfully from it — the advantage it confers is a slightly better count, not a
  better plan. Revisit only if a decision is found to lean on it.
- **Own pieces and neutral features are tracks too**, uniformly — and neutral features are
  DISCOVERED like everything else. Decided 2026-10-06: the fog's unexplored and shaded states
  are the one thing that determines whether the bot is aware of a piece. This retires today's
  deliberate exception for loose Terrestrials, neutral extractors and bunker hosts
  (`bot.gd:989`); liberation, capture, scouting responsibility and the extractor survey read
  tracks instead. Difficulty tiers get no extra information: a very hard bot is tuned, not
  told.
- **Enemy presence is an L1 read.** `believed_structure_count` is a count over the table;
  with the `sight_age` channel's unexplored fraction it is what separates "no structures
  left" from "not found yet" ([bot-engagement-fixes](../bot-engagement-fixes.md) §The controlled
  comparison). L3 only combines the two.

**Per-commander knowledge** sits beside the table, for the few facts worth keeping for the
whole match: two MONOTONE sets that only grow and stay small — the enemy's inferred tech
(seen type X ⇒ owns what `technology_mapping` says produces and unlocks X) and the modifiers
observed (an upgrade seen in effect). This, and the expiring state above, is the entire
memory of the model.

**REJECTED (2026-10-06) — a ledger of own losses.** No mechanic makes a bot that had three
units and lost one play differently from one that always had two. The one consumer, momentum,
is served by the `combat` channel (§L2) instead.

The visual snapshot layer (remembered structure meshes) stays on `CommanderBlackboard` —
it is player-facing rendering, not belief — and reads L1 for what to show.

### L2 — Situation: relations and fields

Derived from L1 once per cadence and stored; a manager never recomputes it.

**Groups.** `enemy_clusters` over BELIEVED tracks, members weighted by confidence
([bot-roadmap](../bot-roadmap.md) §The vision layer), bucketed on the lattice so grouping is
linear rather than O(n²) (same section). Own-side groups the same way, which is the
representation [squads-and-relations](../squads-and-relations.md) needs for "leave half at
home".

**One lattice, and the fields over it** — the three disagreeing quantisations of the ground,
the channel table, the derived reads, and the topology (distance fields, approaches, arrival
time) are [lattice-and-topology](lattice-and-topology.md), `PLANNED`.

**Enemy income** is believed extractors × `EnergyExtractor.energy_rate`, with confidence —
the signal [objective-selection](../objective-selection.md) §First: the signals is blocked on.
**REJECTED (2026-10-06) — an enemy dominion-rate estimate**: a `DominionGenerator` is a piece
with an income affordance and is priced as infrastructure worth killing through the ordinary
utility comparison, which removes the estimate entirely.

**Counter-demand** (`enemy_demand_map`) is computed from the believed composition and the
inferred tech, never from a live `rep` entity (`bot.gd:1395`).

### L3 — Assessment: what it means for me

Reads over L1 and L2, in energy-equivalent units where a value is a value, stored on the
model:

- **Per own asset**: `threat` at its cell and the survivability that follows — the
  per-structure read [bot-roadmap](../bot-roadmap.md) §The gaps in the decision surface asks
  for when picking a producer.
- **Engagements and momentum.** An engagement is a connected region of the lattice where
  `combat` is above threshold; momentum is computed PER ENGAGEMENT, from value destroyed by
  each side inside it (two decaying scalars, overwritten as damage is witnessed). A costly
  winning fight reads as winning, "did that trade well" is a read of the region, and nothing
  is segmented in time ([bot-roadmap](../bot-roadmap.md) §Reading the game).
- **Static-defence demand** (decided 2026-10-06; built on presence 2026-10-07,
  `BotEconomy._defence_demand`, lattice form pending): per own exposed region,
  `value × vulnerability`, in energy-equivalent. A static defence is placed lethality — an
  investment in one region that cannot be moved — so the decision to build one comes from
  this read exceeding the tower's cost, and never from a count. **REJECTED — a
  `defence_structure_target` default.** It made towers an opening purchase by construction
  (three early towers in a clump, observed 2026-10-06 on `main`); the economy's defence rung
  becomes an opportunity priced by this read, placement maximises `reach_coverage` over the
  region's `approach` rather than compactness, and a second tower must clear the demand
  REMAINING after the first's coverage. A tier knob, if wanted, is a propensity weight on the
  demand, not a count.
- **Standing is LOCAL** (decided 2026-10-06). Per own group: its value against the enemy
  influence within its reach. An army beside an exposed enemy position reads a strong standing
  there and a futile one at the base under attack across the map, and attacks where it is —
  no special rule. The global figures (army value, income, control fraction) are sums kept
  for the posture layer, and no decision about a group reads them.
- **Enemy presence**: the L1 count against the L2 unexplored fraction.

### L4 — Attention: what is worth looking at, and where the bot is looking

The model's own output back to itself: a ranked list of *questions*, each priced in
energy-equivalent as stakes × (1 − confidence) — "is the believed base still at X" (stakes:
the whole attack plan), "this resource site read empty three minutes ago" (stakes: its
`value`), "confirm this low-confidence group near my flank". `BotScout`'s
`INFORMATION_VALUE_ENERGY × stale_fraction` is the special case where every cell has equal
stakes. Two consumers read the one ranking: **scouting** (where to send a unit — `BotScout`
and the REVEAL sanction) and **focus** (where the bot looks).

**Focus, rudimentary** (decided 2026-10-06; tune in testing): `k` discs of radius `R` on the
lattice, centred on the top-`k` entries of the ranking, each moving at most one lattice hop
per scout period. L0 delivers sightings only inside a disc; outside, only commander-wide cues
and the coarse fields get through — something is THERE, as a blob on a minimap, without
composition or heading. Starting values: `EASY` k=1, `MEDIUM` k=2, `HARD` k=3, R = 15 world
units; `IMPOSSIBLE` has no discs, its focus is the lattice. The allowance is a
`BotDifficulty` parameter and a MODEL budget; the scheduler's work units are a COMPUTE
budget, and a tier's attention is never defined as what fits in the frame.

### Affordances: the signal the brief asked for

The brief wants a new piece's use to be a matter of data the bot reads, not code written for
it. **Affordances are DERIVED from the components a piece carries, not declared as tags** —
superseding this note's first draft, which proposed a `provides:` tag block (REJECTED
2026-10-06: a tag restates what the component already says, and drifts from it). Each is a
capability × scope × magnitude, and the relational ones (lethality against *this* target)
have a magnitude only once the other party is named. L1 attaches the type's affordance set
to every track; L2 and L3 reason over it, so an enemy sensing provider is worth more than its
cost and a dominion provider is what the dominion drive wants, whatever faction mechanism
produces it.
→ the kinds, the capability table with each derivation, time, attention and cues:
**[ontology.md](../ontology.md)**
