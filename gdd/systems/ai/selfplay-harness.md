---
title: Self-play harness
type: system-note
---

# Self-play harness

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

Headless bot-versus-bot matches with injected parameters, one JSON
result each. This is the instrument [bot-roadmap](bot-roadmap.md) §The training harness asks
for and [bot-parameter-space](bot-parameter-space.md) enumerates the inputs of; what it
measures is not yet decided by anything here.

Files: `tools/selfplay/run_match.gd` + `run_match.tscn` (one match), `run_batch.py` (many),
`example_batch.json` (a batch to copy).

## The one thing to know first

**FIXED (2026-09-05) — see [bot-engagement-fixes](bot-engagement-fixes.md).** The stalemate
below was real and is gone: the same ten configurations now produce **8 decisive results out
of 10**, in 9-17 simulated minutes. §What the first matches found is kept as written,
because it is the measurement that led to the fix, but two of its five items are wrong about
CAUSE and the fixes note says how. Read that note before tuning anything against a match.

*(Originally: a bot-versus-bot skirmish on `skirmish.tscn` ended in a 20-minute stalemate
every time, with no fighting at all — neither commander ever located the other.)*

## Running it

One match:

```
godot --headless --path . --fixed-fps 30 tools/selfplay/run_match.tscn -- \
    config=/abs/path/match.json out=/abs/path/result.json
```

A batch:

```
GODOT=/path/to/godot python3 tools/selfplay/run_batch.py matches.json \
    --out results.jsonl --jobs 2
```

A training run — the population search over the roster, which drives `run_batch.py` itself
([bot-randomness](bot-randomness.md) §Strength is a search):

```
GODOT=/path/to/godot python3 tools/selfplay/train.py seed --cap 900    # roster + round-robin
GODOT=/path/to/godot python3 tools/selfplay/train.py step              # one generation
python3 tools/selfplay/train.py report                                 # no matches run
```

Its state is one directory, `tools/selfplay/results/train/`: the archive, the ledger of every
match played, and the last report. Never run it alongside another Godot process.

**`--fixed-fps 30` is not optional.** It detaches the main loop from wall time, so one engine
iteration is one physics tick and the simulation runs at whatever the CPU can do. Without it
Godot paces physics to the wall clock and a 20-minute match takes 20 minutes. With it, on a
4-core / 3 GB machine, the measured cost is:

| Measured | ticks per wall second |
|---|---|
| one match, opening (few entities) | ~350 |
| one match, sustained over 16 simulated minutes | **~210** |
| `--jobs 2`, aggregate across both | ~560 (≈1.6× one stream) |

**That is the training budget.** A full 20-simulated-minute match is 36,000 ticks: **~170
wall-seconds run alone**, and a `--jobs 2` batch gets through roughly **one match every 105
wall-seconds**. A 200-match sweep is about six hours. Throughput HALVES over a match as
entity counts grow, so a batch of long matches costs more than a short-match measurement
predicts. The pool default is 2 because one match saturates one core and three concurrent
Godots swap on 3 GB; raise it only after measuring `wall_seconds` at the higher setting.

## Input schema

Every key is optional except `slots`, and every default is in `run_match.gd`'s `#region
Defaults`.

```jsonc
{
  "seed": 20260905,                  // Scenario.rng_seed — the whole match's randomness
  "scenario": "res://scenes/scenarios/skirmish.tscn",
  "map_seed": 4217,                  // play on a MapGenerator map from this seed, not the scene's own
  "faction": "res://scenes/factions/colonial.tscn",  // forced onto BOTH slots
  "max_simulated_seconds": 1200,     // 20 minutes — the stalemate cap
  "max_wall_seconds": 900,           // the safety cap; a hung match must not eat a batch
  "sample_interval_seconds": 10,     // set to 0.5 to watch the think loop (see below)
  "state_dump_path": "",             // debugging only: pre-hash state per sample
  "slots": [
    {
      "difficulty": "HARD",          // PASSIVE | EASY | MEDIUM | HARD | IMPOSSIBLE
      "starting_energy": 5000,       // optional, overrides the scene's PlayerSlot
      "starting_dominion": 0,
      "config": {                    // overrides ON TOP of that tier's BotDifficulty
        "combat_period_seconds": 0.333,  // a retired "think_interval_ticks" still sets all three
        "attack_value_ratio": 1.15
      }
    },
    { "difficulty": "MEDIUM" }
  ]
}
```

**`difficulty` selects the starting point and `config` overrides fields on the live object.
The tier table is never edited.** That is the rule the whole harness is built to keep: an
experiment that rewrote `BotDifficulty.for_tier` would be measuring a BUILD rather than a
parameter set, so two parameter sets could not run side by side and no result could name what
produced it. `BotBrain.set_config` is the injection point, and it deliberately leaves
`difficulty` reporting the tier the bot IS while `config` is what it PLAYS BY.

**The searchable field set is read off `BotDifficulty` itself** (via `get_property_list`), not
listed in the harness — a knob added to that class is searchable the moment it exists. An
unknown key is a HARD FAILURE rather than a warning: a search whose parameter was silently
ignored reports a result for an experiment it did not run.

## Output schema

One object, printed between `---SELFPLAY-RESULT-BEGIN---` / `---SELFPLAY-RESULT-END---` on
stdout and written to `out=`. `run_batch.py` appends it to a JSONL with `id` and
`batch_status` (`ok` | `script_error` | `error` | `timeout` | `no_result`) added.

```jsonc
{
  "ok": true,
  "seed": 20260905,
  "map_seed": 4217,             // the generated map actually played (a rejected seed moves on), or -1
  "outcome": "elimination",     // | stalemate | mutual_elimination | wall_clock_cap
  "winner": 0,                  // slot index, or -1
  "ticks": 36000,
  "simulated_seconds": 1200.0,
  "wall_seconds": 171.3,
  "ticks_per_wall_second": 210.2,
  "physics_ticks_per_second": 30,
  "deployed_ticks": [1, 1],     // when each slot first owned anything
  "final_digest": "71da892e568809bd",
  "clean": true,                // false when any GDScript runtime error was raised
  "errors": { "script": 0, "engine": 0, "push_error": 53,
              "top": [ { "kind": "push_error", "count": 51, "message": "...",
                         "at": "res://scripts/utils/space_utils.gd:551 get_nonoverlapping_points" } ] },
  "slots": [ { "slot": 0, "commander_id": 1, "difficulty": "HARD", "faction": "colonial",
               "config": { /* every BotDifficulty field, as played */ },
               "produced_by_id": { /* piece id -> distinct pieces fielded over the match */ },
               "usage": { /* BotUsageLog.summary(): choices, actions, cast_positions */ } } ],
  "samples": [ { "tick": 300, "simulated_seconds": 10.0, "digest": "...",
                 "slots": [ {
                   "energy": 3900, "dominion": 0, "army_energy_value": 600.0,
                   "unit_count": 3, "structure_count": 2, "extractor_count": 0,
                   "income_structure_count": 1,  // built AND building — when income was COMMITTED to
                   "utility_unit_count": 3,      // -1 when the slot is not a Bot and cannot classify a type
                   "brain": {
                     "posture": "MASS",            // MASS | ATTACK | DEFEND
                     "has_attack_objective": false,
                     "believed_enemy_army_value": 0.0,
                     "scout_observed_fraction": 0.05,
                     "scouts_out": 1,
                     "momentum_loss_rate": 0.0,
                     "idle_units": 1
                   } } ] } ],
  "event_log": "/abs/path/result.events.jsonl.gz"   // the match's event log; "" without out=
}
```

**The event log is written beside every result** — gzipped JSON lines, readable with
`gunzip -c` or Python's `gzip`. The harness's verdict is recorded as its `match_ended`. A build
order, energy and army value over time, and purchase counts per piece are all derived from it
rather than from `samples`: [scenario-scripting/match-log](../scenario-scripting/match-log.md).
`run_batch.py` runs each match in a temporary directory and moves its log to
`<results without .jsonl>.events/<id>.events.jsonl.gz` before that directory goes; until
2026-10-07 the logs were deleted with it.

**A verdict reached through a script error is not a result.** With no debugger attached, a
GDScript runtime error does not stop the match: the failing function returns a default and play
goes on, so a match whose bot skipped every decision of one kind still reaches a verdict and
looks clean. `match_error_log.gd` (a `Logger` the harness registers) counts every error by kind
and lists the most frequent with the script line each came from; `run_batch.py` marks a row
whose `clean` is false as `batch_status: "script_error"`. Engine errors and `push_error` are
counted and printed but do not fail a row — an engine error is usually a bug too, but
`push_error` also carries known noise, and failing on it would fail every match.
**In training, one script error invalidates the experiment** (Alex, 2026-10-07): `train.py`
ingests none of that batch, marks the archive invalid with every script error and where it was
raised, and refuses `seed`, `step` and `export` against it; `report` still runs, under a banner.
The errors are fixed, and experimentation restarts in a fresh `--state` directory — ratings
fitted partly through a bug are not salvaged. Any script error counts, not only one in bot
code: a broken piece or projectile corrupts a match as surely as a broken decision.

**Each row carries the parameters it was played with**, so a JSONL of results is
self-describing and a search need not keep the configs that produced it.

**The series is in energy and counts** because energy-equivalent is the currency the bot's own
decisions are priced in ([bot-roadmap](bot-roadmap.md) §The currency is ENERGY-EQUIVALENT) — a
series in the same units as the decision can be read against it.

**The `brain` block is the hysteresis instrument.** Posture, scouts out, whether an attack
objective exists and how many units are idle are oscillations no economy series can show. At
the default 10-second sampling it reads the match; set `sample_interval_seconds` to `0.5`
(about the think cadence) and it reads the think loop.

## Termination

In the order they are checked, each think:

1. **Elimination** — a slot that has DEPLOYED and now owns nothing has lost, **and so has a
   slot that once had a base and now holds no structure and no purchase on its production
   queue.** The survivor is `winner`; both at once is `mutual_elimination`.
2. **Stalemate** — `max_simulated_seconds` of *simulated* time, measured as
   `ticks ÷ TimeUtils.ticks_per_second()`, never as wall clock.
3. **Wall-clock cap** — `max_wall_seconds`. Deliberately the one wall-clock rule in the
   harness: what it guards against is a hang, and a hang is exactly the thing that stops the
   tick counter, so a tick-based cap cannot catch it.

### No structures and no production is a defeat

**This is the rule that was wrong, and it was the largest single distortion in the
measurements.** Elimination used to require owning NOTHING, so a slot reduced to zero
structures and one surviving unit was still "alive" and rode the cap: **23 of the 61
stalemates** in the 2026-09-05 corpus were exactly that shape, and the winner — typically
four or five units in ATTACK posture, several of them idle — never hunted the straggler down.
A match decided at minute 16 was recorded as a draw at minute 20, and the verdict is what the
training objective is computed from, so a wrong verdict is a wrong gradient.

The test is `Commander.has_production_base()`: a structure in play, or an entry on the
production queue. The production half is load-bearing — the last thing a flattened commander
can still have is a funded Build whose builder is walking to the site, and cutting the game
off there would remove exactly the comeback the rule means to allow.

**The same rule now adjudicates the shipped single-player game.** `Scenario._check_player_
eliminated` applies both clauses for the human player, each behind its own arming latch:
`_player_has_deployed` (has ever owned anything) gates the owns-nothing clause, and
`_player_has_had_base` gates the new one — because a mission that opens with units and asks
the player to build would otherwise be lost on frame one. Cover:
`tests/test_Elimination.gd`.

**Elimination is still the harness's job as well, and this is worth knowing.**
`Scenario._check_player_eliminated` returns early when `local_player()` is null, which a
spectator session always is — so a bot-versus-bot match has nothing in the engine adjudicating
it. The harness restates the same rule, latch for latch: owning nothing is the OPENING state
(the opening force is deferred to `NavManager.navmesh_ready`), so a slot must have owned
something before it can lose everything, and must have held a base before it can lose one.

## Determinism

Steps 1–3 of the seeded-pseudo-randomness task are done: `Scenario.rng_seed` is authored,
`Scenario.seed_simulation()` applies it at the top of `_ready`, and every gameplay draw goes
through a seeded generator. Three sites were routed: `Payload.aim_error`,
`EventMortarBarrage._launch_offset` (which the task's audit missed), and — because
`Expression` resolves the @GlobalScope built-ins itself and cannot be redirected — Godot's
GLOBAL generator, seeded from the same number with a salt so the two streams are not one
stream. `tests/test_SeededRandomness.gd` asserts all of it, including a SOURCE SCAN that fails
on any new unseeded draw, because the failure mode is silent: an unseeded draw does not error,
it just makes every measurement taken afterwards mean nothing.

**The bots draw too, from their own streams, and a run of one seed is still one match.** Each brain is seeded from the match seed and its commander id (`BotBrain.seed_randomness`), draws a personality on its first think and samples its scored decisions — so `slots[].config` in a result is the personality as PLAYED, not the tier. An experiment that wants the tier exactly sets `personality_spread: 0` and `decision_temperature: 0` on the slot; one that does not is measuring its own draw. See [bot-randomness](bot-randomness.md).

**Runs of one seed are bit-identical.** Measured 2026-09-29 with navigation synchronous
project-wide: seeds 1 and 3 (HARD vs MEDIUM, 300 simulated seconds) four times each, eight
processes sharing the CPU — every state dump identical, sample for sample. Contention is what a race needs, so running them side by side is the stronger test.

**The "coin flip" was the navmesh, not a draw.** The corpora found one seed taking two
trajectories, first diverging in the opening seconds. The cause was a tick of phase, not a
path: the opening force deploys on `NavManager.navmesh_ready`, readiness is polled against the
navigation server, and the navmesh's CHUNK regions — created by RID in NavManager's deferred
first build — were still async, so the first mesh landed on tick 1 in some runs and tick 2 in
others (1 run in 6, measured). Every bot decision after that ran a tick out of step. The
harness's switch to synchronous iteration walked `NavigationRegion3D` nodes and could never
reach those regions. Navigation is now synchronous project-wide, in `project.godot`, so the
harness does nothing of its own — see [navigation-and-pathing](../terrain-and-navigation/navigation-and-pathing.md)
§Navigation is synchronous, for replay.

The same regions carry every later rebuild — each structure a bot places — so this was also
the likeliest source of the long-run drift once blamed on the RVO avoidance thread pool.

**RVO avoidance is single-threaded, project-wide** (`project.godot`,
`navigation/avoidance/thread_model/avoidance_use_multiple_threads = false`, 2026-10-08). It had
been REJECTED as a fix on the reasoning that the setting does not bind once the world map
exists and that per-agent avoidance is order-independent. Both were wrong: booting one scenario
three times in three processes, the same seed gave three different digests within a second
with multi-threaded avoidance, and three identical runs with it off. The harness had always
forced it off itself (`_force_single_threaded_avoidance`), which is why its runs matched and
the game's would not have.

**A scenario must enter the tree at the same point in the frame to reproduce.** Added during
the physics step, its pieces first process a tick later than when added at idle time, and the
whole match runs a tick out of phase. The game starts scenarios through the scene loader,
always at idle time; a test or probe that boots one twice in a process must do the same
(`await get_tree().process_frame` before `add_child`).

The digest is `SimulationDigest` (game code), shared with replay's drift check — see
[commands/recording-and-replay](../commands/recording-and-replay.md) §Detecting drift.

**Debugging a divergence:** set `state_dump_path` and diff the two runs' dumps. Each line is a
tick and the digest's full pre-hash input, so the first differing line names the entity.

## What the first matches found

Findings, not fixes — all reproducible with `tools/selfplay/example_batch.json`. Written up
here rather than in [bot-roadmap](bot-roadmap.md) because they are measurements of today's
build; the roadmap owns what to do about them.

**1. Two bots never find each other, so a match is a guaranteed stalemate.**
`believed_enemy_army_value` stays at **0.0 for both sides through 16 simulated minutes**.
Scout coverage climbs and then FREEZES — slot 0 at 0.28 from tick 6000, slot 1 at 0.15 from
tick 5400 — with one scout out and never dying. The army meanwhile grows without opposition:
one side reached 50 units and 17,800 energy of army value while the other sat at 9 units and
2,400, and nothing was ever destroyed.

**2. The ATTACK posture is satisfied by a NEUTRAL.** `_objective_for(ATTACK)` takes
`nearest_enemy_structure_to_base()` and then any `get_enemy_units()` — both fog-limited
perception over ANY non-owned commander, and Colonial's dominion route makes neutral
combatants a permanent supply of them. So `has_attack_objective` is true from tick ~300 while
`believed_enemy_army_value` is 0: the bot marches on a neutral, arrives, and stands. It looks
committed and is not fighting anybody.

**3. Unarmed units accumulate idle, monotonically.** 0 → 10 idle units by tick 9000 on one
side. `BotMilitary._combat_units` filters them out of the idle sweep, `scout_unit_budget` caps
the only other claimant at 1, and `BotOpportunist` only has work when it has work — so nothing
ever claims them again. This is [bot-roadmap](bot-roadmap.md) §gap 2 (standing behaviour) with
numbers on it, and the roadmap's own answer — idle defaults to SCOUT — would also fix (1).

**4. Hysteresis was looked for and NOT found at posture level.** *(Re-run after the fixes,
on matches that DO fight: still none. Tick-level evidence in
[bot-engagement-fixes](bot-engagement-fixes.md) §The hysteresis re-check.)* Sampling every 0.5 s (about
the think cadence) over 300 simulated seconds: **2 posture transitions per bot**, both in the
opening, and none afterwards. No retarget flip-flop or posture thrash is visible in these
matches. That is a real negative result and a weak one — a bot that never fights has no
retarget decisions to thrash — so it should be re-run once (1) is fixed.

**5. `Shelter._produce_resident` floods the log** with `Not enough points collected —
requested 1, got 0` from `SpaceUtils.get_nonoverlapping_points`. Pre-existing and unrelated to
the harness, but it is the loudest thing in a match log.

## Known limits

- **One scenario shape.** It boots any `Scenario` whose slots it can rewrite, but everything
  above was measured on `skirmish.tscn`. The focused duel scenes the roadmap wants
  ([bot-roadmap](bot-roadmap.md) §The training harness, item 2) are not built.
- **Two slots.** Nothing assumes it, but nothing has tested three.
- **Both slots get the same faction.** A mirror is what holds everything else equal; a
  cross-faction match needs a per-slot faction key, which is a one-line change nobody has
  needed yet.
- **No replay.** Step 4 of the seeded-randomness task (input recording and playback) is not
  built, so a match is reproducible by re-running it, not by replaying it.
- **The result carries no cause.** It says WHAT happened, never why; the `brain` block is the
  closest thing to a reason and it is six numbers.
