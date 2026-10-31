---
title: Decision pathologies
type: system-note
---

# Decision pathologies: undesirable bot behaviour, and how an omniscient observer detects it

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md
carries only the pointer.*

**Status: TODO, unapproved; first rulings 2026-10-30 (§Rulings).** This is a proposal from a code read of
`feature/bot-difficulty-calibration` at `fdaedd5b` (2026-10-30). No detector is built, and no
threshold below has been fitted. The bugs in §Defects found while mapping are real and checked
against the source.

## What this is for

The difficulty ladder says *who* wins. It does not say whether the loser lost by playing
worse or by doing something stupid, and those are different problems: a bot at EASY should
be **slower and less informed**, never **broken**. [bot-standards](bot-standards.md) asks
"can the bot EXPRESS behaviour X?". This note asks the converse: "when the bot does
something undesirable, how do we notice it, measure it, and say whose fault it is?"

A **pathology** is a decision, or a lack of one, that a competent player in the same position
would not make. It is defined against the TRUE game state, and that is what makes an
omniscient observer the right instrument. A **heuristic** is a measurable function of
(true state, bot belief, bot internals, orders issued) that is large when a pathology is
happening and near zero otherwise. A heuristic emits **episodes**:

```
{ id: "U1", commander, start_s, end_s, severity, attribution, context: { … } }
```

Severity is integrated over time in the currency the bot already prices in (energy-equivalent
× seconds), so episodes from different detectors can be ranked against each other. An
episode carries its start time so a replay can be jumped straight to it.

## Attribution: the four-layer ladder

The observer sees four layers. Every heuristic is evaluated on more than one of them, and
where it first goes wrong names the owner. This is the
[piece-usage audit](piece-usage-audit.md)'s four causes, generalised from pieces to decisions.

| Layer | What the observer reads | If the pathology first appears here, the cause is… |
|---|---|---|
| **T**ruth | every commander's true pieces, positions, hp, queues | — (this is the reference) |
| **B**elief | `CommanderBlackboard.believed()`, `believed_enemy_army_value`, `enemy_value_estimate` | **perception**: the bot doesn't know. Partly *intended*, since tiers vary `perception_delay_seconds`; a belief that never converges is not intended. |
| **D**ecision | posture, objective, `_wave_active`, savings goal, scored choices (`BotUsageLog`) | **decision**: the bot knows and chooses wrong (a scorer, a gate, a threshold) |
| **A**ction | orders issued or refused (`BotUsageLog.actions`), attention balance | **actuation**: the bot decided and the order never went out, or went out and did nothing (`refused:*`, attention starvation, a stuck path) |

A practical rule: compute the heuristic on T. If it fires, recompute it on B (the same
formula over believed quantities). If B agrees, the fault is in D or A; if B disagrees, it is
perception, and the size of the T−B gap is itself a measurement worth plotting per tier.

## Tier policy: which detectors must read zero at every tier

Three classes, so the calibration work can read a detector without re-deciding what it means:

- **DEFECT**: a bug signature. It should be ~0 at every tier, and any non-zero episode is a
  ticket. Example: U2.
- **SKILL**: a weakness that should shrink monotonically from EASY to IMPOSSIBLE. A
  non-monotone detector across tiers is the finding. Examples: P1 float, U6 piecemeal losses.
- **STYLE**: neither good nor bad on its own. It is reported so a change in it is noticed.
  Example: defence share of spend.

The class column in the tables below is a proposal (TODO, Alex to confirm).

## Army utilisation (U)

The headline complaint, "a huge army that never attacks", is U1, and U2–U4 are its
distinguishable causes.

| ID | Pathology | Heuristic (over T unless stated) | Proposed trigger | Attribution read | Class | Data |
|---|---|---|---|---|---|---|
| U1 | **Unused strength**: a strong army stays home. Size is not the fault (Alex, 2026-10-30): a big army is wanted, and the fault is a big army that is not used | `idle_strength = max(0, V_home − k·V_enemy_combat)`, where V_home is own combat value within R_home of own structures, and V_enemy_combat is the enemy's true mobile combat value **plus** static defence value | true ratio `V_own/V_enemy ≥ 1.5`, no own combat unit in the enemy half, for ≥ 90 s; severity = ∫ idle_strength dt | B: the bot's `attack_ratio` vs the true ratio; D: posture, objective, `_wave_active`, sweep | SKILL; a DEFECT while no base threat is believed and the army is neither attacking nor sweeping (see U3) | N: positions |
| U2 | **Committed wave with nowhere to go** (the bug in §Defects) | `_wave_active ∧ posture ≠ ATTACK` | > 5 s | D only; it is a state the code should never hold | DEFECT | D: `wave_active` is in `sample_detail` only. Promote it. |
| U3 | **Objective starvation**: ahead and ready, but no believed target passes the filter, and the army neither attacks nor searches. Ruled (Alex, 2026-10-30): with no known target and no believed reason to defend, the army scouts until it finds one | `ratio ≥ required` with no filtered objective and no sweep point held (note: the sampled `has_attack_objective` means "anything is believed", *before* the filter, so it cannot be used here; read `attack_objective`); split by which filter rejected each believed structure (`can_damage`, `abandoned`, `reachable`, disproved) | > 30 s | B: does the TRUE enemy have structures the army can damage and reach? If none is believed, the army should be sweeping; if one is believed and filtered, the filter | DEFECT | D: per-structure verdicts exist under `sample_detail`; the sweep point is in `debug_state` |
| U4 | **Strength misread**: belief keeps the ratio gate shut (or open) wrongly | `err = believed_enemy_value / true_enemy_value`; ghost share = value of beliefs whose unit is dead or out of play | `err ≥ 1.5` while the gate is shut, or `err ≤ 0.5` while a wave launches into a lost fight (see U5) | B vs T directly | SKILL; a ghost share that never decays is a DEFECT | N: true per-type values per commander |
| U5 | **Attacking into a losing fight** | at each wave launch: `CombatModel.predict(own_wave, enemy_within_R(objective))` on TRUE compositions, statics included; at wave end: trade efficiency `η = enemy value destroyed / own value lost` | predicted loss at launch, or η < 0.5 for a wave | B: the same predict on the believed composition | SKILL | N: wave launch/end events; value destroyed per wave |
| U6 | **Piecemeal losses**: units trickle in and die alone | share of own combat value lost where, at death, friendly combat value within r (≈ max weapon range) was < x·the unit's own value; scouts excluded | isolated-loss share > 0.3 over a 120 s window | D: was the unit rallied straight to the front (`_rally_production`) or ordered alone by `Squad.tick` re-orders? | SKILL | N: death events with position |
| U7 | **Flapping**: posture, wave or objective oscillates | posture changes/min; launch→abort→relaunch within 60 s; objective switches/min; main squad path efficiency = net displacement / path length | > 4 changes/min, or path efficiency < 0.3 over 60 s | D: which input flipped (estimate jump, stall abandonment, regroup expiry) | SKILL; regular-period cycling is a DEFECT | E: posture sampled. N: launch/abort events |
| U8 | **Undefended base**: the enemy is in the base and the army does not come | true enemy answerable value inside R_home, own combat value outside R_home, no DEFEND posture or guard order | > 15 s; severity = own structure value lost during the episode | B: was the threat believed? D: was `can_answer` false? (correct if nothing can hit it; then P4 owns it) | SKILL; DEFECT if suppressed by U2 | N |
| U9 | **Failure to close out**: decisive advantage, no finish | time from first "decisive" sample (true ratio ≥ 3 and enemy income < own/3) to elimination; winner's idle combat value in that window | > 180 s | B: does the bot believe the remaining structures? (the 2026-09-05 stalemates were exactly this shape) | SKILL | E + N |
| U10 | **Idle value**: combat units with no order, outside a station | value-weighted idle fraction, by type (`idle_units` is a count) | > 25% of combat value for > 60 s outside an active wave's regroup | A: claimed by whom (`BotClaims`)? | SKILL | E (count); N (value, per type) |
| U11 | **Garrison sink**: combat value sitting in bunkers while it should be out | combat value garrisoned while a wave is active, or with no enemy within R of the bunker | > 20% of combat value for > 60 s | D: opportunist garrisoning vs `_launch`, the only evacuation path | SKILL | E: `bunkered_units` (count) |
| U12 | **Stuck**: ordered and not moving | units with a move/attack order and displacement < ε over 30 s; sweep/objective points with no path (`nav_probe`) | any unit for > 30 s | A or game bug | DEFECT | N (positions); D (`nav_probe`) |
| U13 | **Arrived and idle at the objective**: target known only by a unit belief, or not yet perceivable | main squad within STALL_RADIUS of its objective, no enemy within weapon range, no Attack issued | > 20 s | B: is the target still true? (ghost-chasing) D: `AssaultPolicy` attacks believed structures only | SKILL | N |
| U14 | **Ability and specialist neglect** | charged-seconds of a castable ability while a valid opportunity existed in truth (e.g. ≥ 2 enemies in blast, no friendlies); kamikaze drones held × seconds; transports, detectors, Bombards owned and unused × seconds | opportunity-seconds > 60 per ability per match | B/D: the usage log's `no_target` vs opportunity in truth separates "can't see it" from "won't do it" | SKILL; `NEVER_AIMED` with true opportunities is a DEFECT | N: opportunity geometry |
| U15 | **Ghost chasing**: marching on a belief that is false | seconds the wave spends heading for an objective with no true enemy at it | > 30 s per wave | B vs T | SKILL (tier-scaled by perception delay) | D + N |
| U16 | **Dead weight**: pieces that never contribute | per piece type: damage dealt + ability effect per energy spent, over the corpus | a type whose fielded instances deal ~0 | piece-usage audit owns the verdict; this adds the *fielded but useless* row it lacks | STYLE → balance | N: damage attribution by source |

## Purchases (P)

| ID | Pathology | Heuristic | Proposed trigger | Attribution read | Class | Data |
|---|---|---|---|---|---|---|
| P1 | **Floating**: money banked with nothing waiting on it | `float = energy − reserve − savings_claim`, while `idle_producers > 0`; severity = ∫ float dt | > 1 minute of own income for > 30 s | D: is a train refused by the reserve, by the claim, or by attention? (not logged today) | SKILL | E: energy, idle_producers, claim |
| P2 | **Phantom savings goal**: a goal that blocks spending and is never bought | goal age (s); goal flips/min; energy held for a goal while the goal is unplaceable or unaffordable for > T | goal age > 90 s with energy ≥ goal cost; > 2 flips/min | D: `BotSavings` has no expiry and no hysteresis | DEFECT past age; flips SKILL | E: `savings_goal` (age derivable) |
| P3 | **Inert purchase**: buying what cannot damage anything the enemy has. Ruled (Alex, 2026-10-30): a candidate inert against every potential target has utility ≤ 0, and 0 means "better off not buying" | share of unit spend on types with `answerable_share = 0` vs the TRUE enemy composition | any, after first contact | B: the same share vs believed; if B also says 0, it is §Defects 2 | DEFECT (when B also 0) | E: `purchase_funded` + N: true composition |
| P4 | **Unanswered threat**: the enemy fields a class the bot cannot hit, and the bot doesn't buy the answer | seconds where the true enemy has value in a layer/class (air, stealth, …) and own answer capacity is 0, while an answer is reachable in the tree; time-to-first-answer | > 120 s | B: believed? D: is the answer valued at its CHAIN cost (Alex, 2026-10-30: prerequisite buildings + the unit; [bot-standards](bot-standards.md) M3)? | SKILL | N |
| P5 | **Composition regret**: buying well below the best available counter | per purchase: `regret = 1 − V(chosen)/V(best)` using `purchase_values_per_energy` on the TRUE enemy composition, where *best* ranges over every unit reachable through the tree at its chain cost (prerequisites unowned + the unit), not only what is trainable now | spend-weighted regret > 0.3 over 120 s | B: regret on believed vs true separates scouting from scoring; temperature sets a floor per tier | SKILL | N: true composition at purchase time |
| P6 | **Useless static defence** | turret spend that never fires; turrets whose weapons cannot target any enemy type present; defence share of spend vs enemy attack pressure. Same rulings as P3 and P5: an inert turret has utility ≤ 0, and a turret behind a prerequisite is valued at its chain cost | a turret with 0 shots over its lifetime; repeated turret builds at value 0 (§Defects 3) | D | DEFECT (repeats at 0); share is STYLE | N: shots fired per piece |
| P7 | **Producers that wait**: more production structures, no more throughput | producers bought while `idle_producers > 0` and float is 0 (money-bound) | any producer bought in that state | D: `_has_resource_surplus` reads `energy ≥ last energy` | SKILL | E |
| P8 | **Economy imbalance** | own income ÷ true enemy income; extractors vs safe available sites; utility units vs `utility_unit_cap` demand | income ratio < 0.7 for > 180 s with sites free and safe; or extractors bought while the base is under answerable threat | B: `enemy_income_estimate` vs true | SKILL | E (+ true enemy income: N) |
| P9 | **Tech stagnation / sunk tech** | first tech time; tech bought whose unlocked units are never trained in the next 180 s | no tech by T (per tier); any sunk tech | D: tech margin vs best unit only | SKILL | E: event log |
| P10 | **Bank raids**: research or sanctions spending a held bank | research funded while `savings_claim > 0` and the goal is unbought (§Defects 4) | any | D. Alex, 2026-10-30: noted, low priority — about a dozen research items per faction, so it stops blocking once they are bought; worth revisiting | SKILL (demoted from DEFECT) | E: event log + claim |
| P11 | **Churn** | `purchase_refunded` per minute; structures cancelled or destroyed before completion | > 1/min; any foundation lost to an enemy in view at placement time | D/A | SKILL | E |
| P12 | **Sanction waste** | dominion spent on cells never cast in the match; charged-but-unaimed seconds | a cell unlocked and never cast | D: `_unlock_affordable` has no valuation | SKILL | E: `usage.actions` |
| P13 | **Defection time** | seconds in `Commander.is_in_defection()` | > 10 s | D: infrastructure rung | SKILL | N (cheap) |

## Cross-cutting (X)

| ID | Pathology | Heuristic | Class |
|---|---|---|---|
| X1 | **Attention starvation** | seconds with `attention_balance < 0`, by which job was waiting; the military's latency from "should change posture" (T) to the order | SKILL by design (it *is* the tier knob); a job starved for > 60 s is a DEFECT |
| X2 | **Belief convergence** | per tier: median and 95th percentile of `believed − true` enemy value; ghost share | SKILL; non-convergence is a DEFECT |
| X3 | **Opportunity cost summary** | per match: Σ U1 + P1 severity as a share of total energy earned. This is "how much of its economy the bot wasted" in one number | SKILL |

## How to build the observer

**Recommendation: compute raw signals live, detect episodes offline.** (TODO, Alex to decide
whether to do this in a replay post-pass or live.)

1. **Raw signals in the harness.** `run_match.gd` already samples the bot's internals and
   records a replay. Add an omniscient `truth` block per sample, which a spectator harness
   can read without touching the bot:
   - per commander: true combat value (mobile and static) and composition by type;
     value inside R_home; income;
   - per wave: launch, end and abort events with value at each, plus value destroyed;
   - deaths with position, type, value and nearby friendly value;
   - `wave_active` and `required_attack_ratio` promoted from `sample_detail` to the default
     sample (cheap, and it covers U2 and U3).
2. **Episodes in Python.** A `pathologies.py` beside `piece_usage.py` reads the result JSONL
   and the event log and emits the episode list. Thresholds live in one table there, so tuning
   a threshold never needs a re-run.
3. **Replay as the second pass.** Matches are deterministic and recorded, so a detector that
   needs geometry (U6, U12, U14) can be run against a replay of only the matches whose cheap
   signals flagged them, rather than paying for geometry in every ladder match.
4. **Report beside the ladder table.** Per tier: episodes per match and total severity for
   each detector. The monotonicity check is what makes the tier-policy classes testable.

Each DEFECT-class detector should also become a decision sim
([decision-sims](decision-sims.md)) once its bug is fixed, so the regression is pinned
without a ladder run.

## Defects found while mapping (2026-10-30)

Each one is checked against the source. None is fixed.

1. **A committed wave with no destination, which never defends** (`bot_military.gd`).
   - `_committing_to_attack` sets `_wave_active = true` before an objective exists.
   - When `_objective_for(ATTACK)` is null, `_sweep_objective` refuses, because the main squad
     never took an `AssaultPolicy`. The posture falls back to MASS.
   - `_wave_active` stays true, so `_decide_posture` returns ATTACK from its first branch on
     every later think, and DEFEND is unreachable.
   - The stalemate clock is frozen. Only a momentum-confirmed loss to below
     `wave_abort_fraction` ends it.
   - Signature: U2. By the 2026-10-30 ruling the army in this state should be searching:
     the sweep's "only a wave already marching" condition is what refuses it.
2. **The inert cut re-ranks but never vetoes** (`BotProduction._best_unit_for`). When every
   candidate scores ≤ 0, `BotSampling._weights` returns empty and `_argmax` returns 0, so
   `types[0]` is trained. Signature: P3.
3. **The defence rung can build useless turrets repeatedly**
   (`BotEconomy._defence_structure_to_build`). It returns `candidates[0]` at value 0 with no
   answerable cut, and a turret that cannot hit the threat does not reduce the region's
   demand. Signature: P6.
4. **Research ignores the savings claim** (`BotResearch._worth_buying` checks only the
   reserve). Signature: P10. Noted, low priority (§Rulings).

A parameter note rather than a defect: `enemy_value_estimate` is floored at
`own × assumed_enemy_parity`, so `attack_ratio ≤ 1/parity ≈ 1.18`. That means
`attack_value_ratio = 1.3` is never met directly, and every launch waits on the stalemate
relaxation (about 6 s). Above about 1.18 the parameter has no effect
([bot-parameter-space](bot-parameter-space.md), T-099).

## Rulings (Alex, 2026-10-30)

- **A big army is not the fault.** Bots should buy more, not less; how much is the
  difficulty parameterisation's job. The pathology is a big army that is not USED — U1 is
  reframed accordingly.
- **No army ceiling as a game mechanic.** Unlimited army size is fine: time to kill is low,
  so large armies thin out quickly. No supply-style cap.
- **A unit ceiling may be a difficulty throttle.** PLANNED as bot modelling, never a game
  rule: a lower tier may cap how many units it eventually produces. Out of scope for this
  note; it belongs with the tier parameters ([bot-parameter-space](bot-parameter-space.md)).
- **No known target means search, not mass.** With nothing to attack and no believed reason
  to defend, the army scouts until it finds something (U3, §Defects 1). Scouting was flagged
  in another session as the lowest-priority job and Alex asked for it to be reprioritised; on
  `fdaedd5b` the scout job is still served last.
- **Inert means utility ≤ 0.** A purchase option inert against every potential target is
  valued at or below 0, and 0 can mean "do not buy" (§Defects 2, 3).
- **Value an option through the tree.** An unowned prerequisite is part of the price: the
  effective cost of a unit from an unbuilt building is the building's cost plus the unit's
  (the M3 TODO in [bot-standards](bot-standards.md)). Applies to units and to defence
  structures alike.
- **Research vs the savings claim** stays noted and unprioritised (P10).

## Open questions

> **TODO: what "should have attacked" means.** U1's trigger (ratio 1.5, 90 s, nothing in
> the enemy half) is still a placeholder to fit against the corpus.

> **TODO: scope.** The ladder plays Colonial mirrors. Should the detectors be validated on
> Anarchical too before they're trusted?
