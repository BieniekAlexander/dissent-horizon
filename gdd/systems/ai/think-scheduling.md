---
title: Think scheduling
type: system-note
---

# Think scheduling

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

A bot's thinking is a set of **jobs**, each on its own period, run by one **BotScheduler** per
session against a shared per-tick budget counted in **work units**. Which manager owns which
unit is stated in a **BotClaims** registry, not implied by which manager ran first. Built
2026-09-26, on Alex's direction: *a think is expected to evaluate within a budget that need not
follow the physics tick rate, and each kind of evaluation gets its own cadence — combat often,
scouting far less often.*

The code carries the mechanism (`bot_scheduler.gd`, `bot_job.gd`, `bot_claims.gd`,
`BotBrain._build_jobs`). This note keeps what it cannot: why it is shaped this way, the
rules the code relies on, and what is still open.

## Why

`BotBrain` used to run `think()` whole every N physics ticks: all nine managers, in order,
inside one tick. Measured on the 261×261 skirmish map ([bot-performance](bot-performance.md)),
a think tick cost 40–185 ms, both bots' landed on the same tick, and the cost grew with army
size and map area. A slower cadence only made the spike rarer.

## How other RTS engines do it

None of the engines whose source is public measure a time budget. They make the cost small
by construction and spread it:

- **0 A.D. (Petra bot): fixed staggering by turn number.** The headquarters runs each
  sub-manager on its own residue: `playedTurn % 4 == 0` trains workers, `== 1` builds
  houses, `== 2` farmsteads, `% 5 == 1` research, `% 10 == 7` expansion, and so on
  ([headquarters.js](https://raw.githubusercontent.com/0ad/0ad/master/binaries/data/mods/public/simulation/ai/petra/headquarters.js)).
  The AI runs synchronously on the simulation thread. The engine tried a worker thread and
  gave it up because copying the game state every turn was itself too slow; there is no time
  budget, only a TODO wishing for one
  ([CCmpAIManager.cpp](https://raw.githubusercontent.com/0ad/0ad/master/source/simulation2/components/CCmpAIManager.cpp)).
- **Spring / Beyond All Reason: a slow update spread across units.** Each unit's
  `SlowUpdate` runs every `UNIT_SLOWUPDATE_RATE = 15` frames of a 30 fps sim, with
  `activeUnits.size() / 15 + 1` units per frame, so the load is even, not bursty
  ([UnitHandler.cpp](https://raw.githubusercontent.com/beyond-all-reason/spring/master/rts/Sim/Units/UnitHandler.cpp),
  [GlobalConstants.h](https://raw.githubusercontent.com/beyond-all-reason/spring/master/rts/Sim/Misc/GlobalConstants.h)).
- **Supreme Commander: every platoon and manager is a Lua coroutine** that yields with
  `WaitTicks`/`WaitSeconds`, so decision work is interleaved with the sim by construction
  ([Supreme Commander Wiki: Lua](https://supcom.fandom.com/wiki/Lua)).

What they share, and what this proposal keeps: **work is cut into slices small enough that
no single tick carries much of it.** None of them measures wall-clock time either; see
§Rejected for why this one does not.

## The rules

- **Periods are in seconds, per group of jobs** (`BotDifficulty.combat_period_seconds`,
  `strategy_period_seconds`, `scout_period_seconds`), converted to ticks once, in
  `BotJob.period_ticks`. Kamikaze evaluation and unit preservation have fixed periods of their
  own. The tiers ship with one period for everything — the reaction time each had under the
  single think interval — so the split changed no tier's pace; tuning the periods apart is the
  self-play search's job. Nothing is counted in *thinks* any more, which removes what
  [bot-parameter-space](bot-parameter-space.md) called the biggest confound in the space.
- **Due jobs run earliest-due first, then by job priority** (combat before strategy before
  scouting), then in registration order. A short budget therefore delays scouting, not a
  fight, and nothing starves: a waiting job's due tick only gets older.
- **The budget is counted in work units, never in wall-clock time,** so a seed makes the same
  decisions on every machine. One unit is calibrated to roughly a microsecond on the machine
  the costs were measured on; each manager names its per-operation costs as constants.
  Wall-clock time is recorded per job (`BotScheduler.report`) and never read by a decision.
- **An overspend is debt.** A job that cannot stop part-way reports what it cost, and later
  ticks pay the debt off before anything else runs, so the budget holds on average.
- **A sweep that can grow large is resumable**, with an explicit cursor rather than an `await`:
  the scout's sight sweep, the scout's errand search, and the economy's build-spot search. Each
  resumes on the next tick and does at least one step per call, so it can never stall.
- **Claims replace order.** A manager that tasks a unit claims it; the army is whatever nobody
  has claimed. Priorities: scouting < combat (BotTargeting mid-fight) < errands (a build job,
  a capture or deposit run, a liberation) < exclusive (kamikaze drones). A stronger claim takes
  the unit; equal claims never take from each other. Each owner releases when its errand ends.
  This is what used to be "the scout runs before the military's idle sweep".

## Measured

Same spectator skirmish as [bot-performance](bot-performance.md), ~7,000 ticks each:

| Bot time per tick | Before | After |
|---|---|---|
| p95 | 4.5 ms | 0.9 ms |
| p99 | 63 ms | 2.8 ms |
| ticks over 33 ms | 200 | 2 |
| mean | 2.05 ms | 0.24 ms |

The last two spikes were the economy's build-spot search (115 ms) and the scout's errand search
(~27 ms); both were made resumable after that run.

## Open

- **TODO — the AI's share of a tick** (gdd/deferred.md 1.38) is Alex's to set.
  `BotScheduler.WORK_UNITS_PER_TICK` is a provisional 2000 units, ~2 ms.
- **TODO — a debug-build wall-clock tripwire** (Decision 1's option 3) was not built: nothing
  reports a job whose work units have drifted from its real cost. Re-run the calibration
  (`tools/_perf_probe_tmp.tscn`, whose output ends with µs per unit per job) after changing a
  manager's loops.
- **TODO — the per-operation weights are coarse.** They were fitted per job, not per operation,
  from one match; a job that mixes cheap and expensive steps (the economy) is only right on
  average.

## Rejected

- **REJECTED — a wall-clock budget.** It holds on any machine, but the same seed would play a
  different match depending on CPU speed and load, and self-play and replays stop being
  reproducible.
- **REJECTED — keeping the run order, by declaring dependencies between jobs.** Tied jobs would
  have to share a cadence, giving back what independent periods were for.
- **REJECTED — "has a command" as the ownership test.** It cannot tell a scout's waypoint from
  an attack-move the military meant to override.
- **REJECTED — a worker thread for the think.** 0 A.D. tried it and backed out (the state
  copy costs more than it saves). Here the managers read the live scene tree, and Godot's
  scene tree is not thread-safe.
- **REJECTED (2026-09-25, for now) — a simulation-harness gate** that fails a run whose think
  time exceeds a budget.
