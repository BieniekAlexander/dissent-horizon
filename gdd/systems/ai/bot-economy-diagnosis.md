---
title: Bot economy diagnosis
type: system-note
---

# Bot economy diagnosis

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

**FIXED (2026-09-05).** Why a bot with an `economy_reserve` was broke in 70% of every sampled
tick, why `economy_reserve = 1500` produced a simulation bit-identical to `600`, and why the
matches that stalemate go flat and stay flat. One cause explains all three. The instrument is
[selfplay-harness](selfplay-harness.md); the corpus re-analysed is
the 85-match run of 2026-09-05.

## The answer, plainly

**The bot was broke because it had no income at all.** It never built a single extractor: in
the 85-match corpus, **145 of 170 slot-trajectories finished owning zero extractors**, and
every unmodified MEDIUM mirror in it — 20 of 20 — had an energy collection rate of exactly
`0.0` for the whole match. The bot spent its 5,000-energy starting grant on buildings and
units in the first two minutes and was then penniless for the rest of the game.

**`economy_reserve` could not stop that, because it was never a floor.** It was a TRIGGER —
"am I rich enough to consider expanding?" — and nothing anywhere refused a purchase for
breaching it. `BotProduction` trained on plain affordability and never read the threshold at
all; `BotEconomy`'s own structure purchases only asked `can_afford`. A bot at 700 energy with
a 600 reserve would buy a 900-energy building the moment it cleared 1,500 and be under the
reserve again before the next think.

**And the reserve was gating the wrong branch.** `BotEconomy.tick()` built income only in the
`else` of the surplus test — that is, only once the balance had fallen BELOW the reserve. With
MEDIUM's reserve of 600 and an extractor priced at 500, the bot was permitted to buy income
only inside a 100-energy window, and the two ungated spenders stepped straight over it. Above
the window it would not buy income; below it, it could not afford it.

## The measurement

Same runner, same map, same MEDIUM-mirror configuration, seeds 11, 12, 101–104 (+13–18 after).

| | zero-energy | zero-extractor slot-trajectories | peak extractors |
|---|---|---|---|
| **Before** — corpus MEDIUM mirrors, first 300 s (n=20) | **63.4%** of samples | 20 / 20 | 0.00 |
| **Before** — corpus MEDIUM mirrors, full length (n=20) | **85.7%** of samples | 20 / 20 | 0.00 |
| **Before** — whole 85-match corpus (n=170) | **70.4%** of samples | 145 / 170 | — |
| **After** — 12 matches, 300 s (n=24) | **1.6%** of samples, 1.69% of *physics ticks* | **0 / 24** | 3.67 mean |

Paired on one seed, with a per-tick ledger rather than 10-second samples: seed 11, 300 s,
**5,900 / 9,000 ticks at exactly zero energy before, 133 / 9,000 after.**

**The reserve now binds.** Ticks with the balance at or above the 600 reserve went from
**17.6% to 63.2%**. Before the fix `economy_reserve` was being evaluated at a corner it never
left, which is the mechanical reason 1500 and 600 produced the same simulation; the corpus's
group-A "NOT WIRED" verdict for that field should be re-run rather than believed.

## The flat stalemate is the same bug

The corpus's stalemated matches go flat because **neither side can afford to rebuild
anything**, not because either side decides not to. Mean over slot-trajectories:

| t (s) | before: army / structures / energy | after: army / structures / energy |
|---|---|---|
| 60 | 2094 / 5.0 / 267 | 1967 / 5.2 / 267 |
| 120 | 2262 / 5.0 / **0** | 1958 / 6.2 / 267 |
| 240 | 1347 / 4.9 / **0** | 2553 / 10.0 / 1327 |
| 360 | 1018 / 4.2 / **0** | 6117 / 14.6 / 1954 |
| 420 | 896 / 4.0 / **0** | 8188 / 16.5 / 2067 |
| 600 | 802 / 3.0 / **0** | *(not run — see §Budget)* |
| 1200 | 812 / 2.5 / **0** | *(not run)* |

Before, army value peaks at minute 2 and then decays monotonically to ~810 and holds; energy
is exactly zero from minute 2 onward. After, it dips at the first exchange and then climbs
through every subsequent bucket. **The bot was not failing to notice it was behind — it was
bankrupt.** Two earlier sessions concluded the next thing to build is an income SENSE; that
conclusion was drawn on a corpus in which every commander's income was identically zero, so
there was nothing for a sense to distinguish. The sense may still be worth building, but the
flat stalemate does not need it as an explanation.

## What changed

Both defects had to go together: a floor with no income to protect would simply park the
balance at the reserve forever.

- **`scripts/interface/commander/bot_economy.gd`** — `can_afford_above_reserve()` makes the
  reserve a FLOOR as well as a trigger, and gates the production-capacity rung on it. Income,
  infrastructure and dominion structures are deliberately EXEMPT: those are the purchases the
  bank exists to keep affordable. The surplus branch now FALLS THROUGH to income when it has
  nothing to add to throughput, instead of returning. `_income_build_spot()` was extracted so
  the income rung has the same (type, spot) shape as the other two.
- **`scripts/interface/commander/bot_production.gd`** — a `reserve` field, and training is
  gated on `_can_afford_above_reserve` at the single place this manager spends. What the bot
  WANTS is unchanged; only whether it may buy it now.
- **`scripts/interface/commander/bot_brain.gd`** — one line: `_apply_config` pushes
  `economy_reserve` to the production manager as well as the economy one.
- **`tests/test_BotEconomyReserve.gd`** — nine tests pinning both defects.

This makes `economy_reserve` mean what [bot-roadmap](bot-roadmap.md) §The currency is
ENERGY-EQUIVALENT says it means — "stop the bot spending down to zero so that it can always
afford something" — and leaves it a threshold, which that section is explicit about wanting
for now.

## What this does NOT settle

**The opening ladder ordering is still throughput-first.** The bot spends its whole starting
grant on production structures and completes its first extractor at a mean of **125 s** (min
120, max 130, n=24). That is late for an RTS opening, and it is an ORDERING decision — the one
half of the ladder that is not a number — so it is not being changed here. See the open
question on the task.

> **SETTLED (2026-09-05).** That rung is a number now, and a number the game bends:
> `BotDifficulty.income_structure_target` (default 1) × `BotEconomy.safety()`. First extractor
> **120 s → 60 s**, measured on a six-seed MEDIUM mirror; the site is claimed at 40 s rather
> than 100 s. Write-up, the full before/after series and the cost side of the trade:
> [bot-architecture](bot-architecture.md) §The opening's income rung reads the game.
>
> It also exposed a latent freeze this note's own argument explains. The pre-fix ladder reached
> for an extraction site only when it was too poor to do anything else — the same corner
> `economy_reserve` was evaluated at — so nobody had noticed that a `Build` which never
> completes holds the bot's only construction slot and stops the whole economy. Making the
> income rung fire early made it common (537 of 539 think passes taking the "already building"
> exit, in an instrumented match). Guarded in
> `BotEconomy._release_stalled_construction`; see [bot-architecture](bot-architecture.md)
> §A build that never finishes.

**No claim is made about strength.** Every match measured is a mirror, so both sides got the
fix and the win rate cannot move. What is measured is that the economy runs; whether a richer
bot is a better opponent is a round-robin question, and the 2026-09-05 archetype
matrix should be re-run before its
"ECONOMIST dominates" reading is trusted — ECONOMIST's edge was, mechanically, that a high
reserve and four concurrent builds were the only configuration that *accidentally* landed the
balance inside the 100-energy income window. Peak extractors by configuration, from the
corpus: MEDIUM baseline 0.00 (n=117), `production_structure_cap = 3` 3.57, ECONOMIST 5.43.

## Budget, and what it costs to measure now

**A working economy makes matches expensive.** Post-fix, a MEDIUM mirror runs at ~152 ticks
per wall second against the harness note's ~210 median, because entity counts roughly triple
(structures 2.5 → 16.5 by minute 7). A 20-minute match no longer fits in the ~170 wall-seconds
[selfplay-harness](selfplay-harness.md) quotes. Plan the next sweep against the new figure,
and re-measure it — this note's after-set is 15 matches and 21 core-minutes, all at 300–470
simulated seconds.

## The instrument

`tools/selfplay/_economy_match.gd` + `.tscn` — a TEMPORARY probe subclassing
`run_match.gd` (the `_debug_match.gd` pattern). It adds, per sample: committed-but-unpaid
energy, collection and spend rates, the reserve and whether the balance is above it, the
buildable sets `BotEconomy` derives and which of them it can afford, and a per-PHYSICS-TICK
ledger of debits attributed to TRAIN or BUILD. It reads only; it never issues.

**One thing it taught that is worth keeping:** a debit cannot be observed from
`ProductionQueue.entries`. `submit()` calls `tick()` synchronously, so an affordable purchase
is submitted, funded, dispatched and removed inside one call and is never in the queue on a
later frame. TRAIN debits are observable at the producer (`Production.training_queue`); BUILD
debits are not observable from either, which is why the ledger's `build_energy` reads zero and
the BUILD side of this note is argued from structure counts instead.

**Ruled out early, and cheaply:** the balance is not zero because the queue holds the state.
`energy_committed()` was zero at every sample of every match, before and after, and
`production_queue` was empty at every tick — the bot really was broke, not merely committed.
